module Compute
  class InstancesController < Compute::ApplicationController
    before_filter :all_projects
    before_action :automation_data, only: [:new, :create]

    authorization_context 'compute'
    authorization_required except: [:new_floatingip, :attach_floatingip, :detach_floatingip, :new_snapshot]

    def index
      params[:per_page]= 20
      @instances = []
      if @scoped_project_id
        @instances = paginatable(per_page: (params[:per_page] || 20)) do |pagination_options|
          ServerNG.all(@admin_option.merge(pagination_options))
        end

        # get/calculate quota data for non-admin view
        unless @all_projects
          usage = services.compute.usage

          @quota_data = services.resource_management.quota_data([
            {service_name: :compute, resource_name: :instances, usage: usage.instances},
            {service_name: :compute, resource_name: :cores, usage: usage.cores},
            {service_name: :compute, resource_name: :ram, usage: usage.ram}
          ])
        end
      end

      # this is relevant in case an ajax paginate call is made.
      # in this case we don't render the layout, only the list!
      if request.xhr?
        render partial: 'list', locals: {instances: @instances}
      else
        # comon case, render index page with layout
        render action: :index
      end
    end

    def console
      @instance = ServerNG.find(params[:id])
      @console = @instance.vnc_console
      respond_to do |format|
        format.html{ render action: :console, layout: 'compute/console'}
        format.json{ render json: { url: @console.url }}
      end
    end

    def show
      @instance = ServerNG.find(params[:id])
      @instance_security_groups = @instance.security_groups_details.collect do |sg|
        services.networking.security_groups(tenant_id: @scoped_project_id, id: sg.id).first
      end
    end

    def new
      # get usage from db
      @quota_data = services.resource_management.quota_data([
        {service_type: :compute, resource_name: :instances},
        {service_type: :compute, resource_name: :cores},
        {service_type: :compute, resource_name: :ram}
      ])

      @instance = services.compute.new_server

      @flavors            = services.compute.flavors
      @images             = services.image.all_images

      azs = services.compute.availability_zones
      if azs
        @availability_zones = azs.select { |az| az.zoneState['available'] }
        @availability_zones.sort_by!{|az| az.zoneName}
      else
        @instance.errors.add :availability_zone, 'not available'
      end

      @security_groups = services.networking.security_groups(tenant_id: @scoped_project_id)
      @private_networks   = services.networking.project_networks(@scoped_project_id, "router:external"=>false) if services.networking.available?

      @keypairs = services.compute.keypairs.collect {|kp| Hashie::Mash.new({id: kp.name, name: kp.name})}

      @instance.errors.add :private_network,  'not available' if @private_networks.blank?
      @instance.errors.add :image,            'not available' if @images.blank?

      # @instance.flavor_id             = @flavors.first.try(:id)
      # @instance.image_id              = params[:image_id] || @images.first.try(:id)
      @instance.availability_zone_id  = @availability_zones.first.try(:id)
      @instance.network_ids           = [{ id: @private_networks.first.try(:id) }]
      @instance.security_group_ids    = [{ id: @security_groups.find { |sg| sg.name == 'default' }.try(:id) }]
      @instance.keypair_id = @keypairs.first['name'] unless @keypairs.blank?

      @instance.max_count = 1
    end


    # update instance table row (ajax call)
    def update_item
      @instance = ServerNG.find(params[:id]) rescue nil
      @target_state = params[:target_state]

      respond_to do |format|
        format.js do
          if @instance and @instance.power_state.to_s!=@target_state
            @instance.task_state||=task_state(@target_state)
          end
        end
      end
    end

    def create
      @instance = services.compute.new_server
      params[:server][:security_groups] = params[:server][:security_groups].delete_if{|sg| sg.empty?}
      @instance.attributes=params[@instance.model_name.param_key]

      if @instance.save
        flash.now[:notice] = "Instance successfully created."
        audit_logger.info(current_user, "has created", @instance)
        @instance = ServerNG.find(@instance.id)
        render template: 'compute/instances/create.js'
      else
        @flavors = services.compute.flavors
        @images = services.image.images
        @availability_zones = services.compute.availability_zones
        @security_groups = services.networking.security_groups(tenant_id: @scoped_project_id)
        @private_networks   = services.networking.project_networks(@scoped_project_id).delete_if{|n| n.attributes["router:external"]==true}
        @keypairs = services.compute.keypairs.collect {|kp| Hashie::Mash.new({id: kp.name, name: kp.name})}
        render action: :new
      end
    end

    def new_floatingip
      enforce_permissions("::networking:floating_ip_associate")
      @instance = ServerNG.find(params[:id])
      collect_available_ips

      @floating_ip = Networking::FloatingIp.new(nil)
    end

    def attach_floatingip
      enforce_permissions("::networking:floating_ip_associate")
      @instance_port = services.networking.ports(device_id: params[:id]).first
      @floating_ip = Networking::FloatingIp.new(nil,params[:floating_ip])

      success = begin
        @floating_ip = services.networking.attach_floatingip(params[:floating_ip][:ip_id], @instance_port.id)
        if @floating_ip.port_id
          true
        else
          false
        end
      rescue => e
        if e.type == 'NotFound'
          @floating_ip.errors.add('Error:', 'Could not attach floating IP to server. Please verify that a router between private and floating ip network exists.')
        else
          @floating_ip.errors.add('message', e.message)
        end
        false
      end

      if success
        audit_logger.info(current_user, "has attached", @floating_ip, "to instance", params[:id])

        respond_to do |format|
          format.html{redirect_to instances_url}
          format.js{
            @instance = ServerNG.find(params[:id])
            addresses = @instance.addresses[@instance.addresses.keys.first]
            addresses ||= []
            addresses << {
              "addr" => @floating_ip.floating_ip_address,
              "OS-EXT-IPS:type" => "floating"
            }
            @instance.addresses[@instance.addresses.keys.first] = addresses
          }
        end
      else
        collect_available_ips
        render action: :new_floatingip
      end
    end

    def detach_floatingip
      enforce_permissions("::networking:floating_ip_disassociate")
      begin
        floating_ips = services.networking.project_floating_ips(@scoped_project_id, floating_ip_address: params[:floating_ip]) rescue []
        @floating_ip = services.networking.detach_floatingip(floating_ips.first.id)
      rescue => e
        flash.now[:error] = "Could not detach Floating IP. Error: #{e.message}"
      end

      respond_to do |format|
        format.html{
          sleep(3)
          redirect_to instances_url
        }
        format.js{
          if @floating_ip and @floating_ip.port_id.nil?
            @instance = ServerNG.find(params[:id])
            addresses = @instance.addresses[@instance.addresses.keys.first]
            if addresses and addresses.is_a?(Array)
              addresses.delete_if{|values| values["OS-EXT-IPS:type"]=="floating"}
            end
            @instance.addresses[@instance.addresses.keys.first] = addresses
          end
        }
      end
    end

    def attach_interface
      @os_interface = services.compute.new_os_interface(params[:id])
      @networks = services.networking.networks("router:external"=>false)
    end

    def create_interface
      @os_interface = services.compute.new_os_interface(params[:id],params[:os_interface])
      if @os_interface.save
        @instance = ServerNG.find(params[:id])
        respond_to do |format|
          format.html{redirect_to instances_url}
          format.js{}
        end
      else
        @networks = services.networking.networks("router:external"=>false)
        render action: :attach_interface
      end
    end

    def detach_interface
      @instance = ServerNG.find(params[:id])
      @os_interface = services.compute.new_os_interface(params[:id])
    end

    def delete_interface
      # create a new os_interface model based on params
      @os_interface = services.compute.new_os_interface(params[:id],params[:os_interface])

      # load all attached server interfaces
      all_server_interfaces = services.compute.server_os_interfaces(params[:id])
      # find the one which should be deleted
      interface = all_server_interfaces.find do |i|
        i.fixed_ips.first['ip_address']==@os_interface.ip_address
      end

      success = if interface
        # destroy
        @os_interface.id = @os_interface.port_id = interface.port_id
        @os_interface.destroy
      else
        @os_interface.errors.add(:address,'Not found.')
        false
      end

      if success
        # load instance after deleting os interface!!!

        # try to update instance state
        timeout = 60
        sleep_time = 3
        loop do
          @instance = ServerNG.find(params[:id])
          if timeout<=0 or @instance.addresses.values.flatten.length==all_server_interfaces.length-1
            break
          else
            timeout -= sleep_time
            sleep(sleep_time)
          end
        end
        respond_to do |format|
          format.html{redirect_to instances_url}
          format.js{}
        end
      else
        @instance = ServerNG.find(params[:id])
        @os_interface.ip_address=params[:os_interface][:ip_address]
        render action: :detach_interface
      end
    end

    def new_size
      @instance = ServerNG.find(params[:id])
      @flavors  = services.compute.flavors
    end

    def resize
      @close_modal=true
      execute_instance_action('resize',params[:server][:flavor_id])
    end

    def new_snapshot
    end

    def create_image
      @close_modal=true
      execute_instance_action('create_image',params[:snapshot][:name])
    end

    def confirm_resize
      execute_instance_action
    end

    def revert_resize
      execute_instance_action
    end

    def stop
      execute_instance_action
    end

    def start
      execute_instance_action
    end

    def pause
      execute_instance_action
    end

    def suspend
      execute_instance_action
    end

    def resume
      execute_instance_action
    end

    def reboot
      execute_instance_action
    end

    def destroy
      execute_instance_action('terminate')
    end

    def automation_script
      accept_header = begin
        body = JSON.parse(request.body.read)
        os_type = body.fetch('vmwareOstype', '')
        if os_type.include? "windows"
          "text/x-powershellscript"
        else
          "text/cloud-config"
        end
      rescue => exception
        Rails.logger.error "Compute-plugin: automation_script: error getting os_type: #{exception.message}"
      end
      script = services.automation.node_install_script("", {"headers" => { "Accept" => accept_header }})
      render :json => {script: script}
    end

    def automation_data
      @automation_script_action = automation_script_instances_path()
    end

    def two_factor_required?
      if action_name=='console'
        true
      else
        super
      end
    end

    def edit_securitygroups
      @instance = ServerNG.find(params[:id])
      @instance_security_groups = @instance.security_groups_details
      @instance_security_groups_keys = []
      @instance_security_groups.each do |sg|
        @instance_security_groups_keys << sg.id
      end
      @security_groups = services.networking.security_groups(tenant_id: @scoped_project_id)
    end

    def assign_securitygroups
      @instance = ServerNG.find(params[:id])
      @instance_security_groups = @instance.security_groups_details
      @instance_security_groups_ids = []
      @instance_security_groups.each do |sg|
        @instance_security_groups_ids << sg.id
      end

      to_be_assigned = []
      to_be_unassigned = []

      sgs = params['sgs']
      if sgs.blank?
        flash.now[:error] = "Please assign at least one security group to the server"
        @instance = ServerNG.find(params[:id])
        @instance_security_groups = @instance.security_groups_details
        @instance_security_groups_keys = []
        @instance_security_groups.each do |sg|
          @instance_security_groups_keys << sg.id
        end
        @security_groups = services.networking.security_groups(tenant_id: @scoped_project_id)
        render action: :edit_securitygroups and return
      else
        sgs.each do |sg|
          to_be_assigned << sg unless @instance_security_groups_ids.include?(sg)
        end
        @instance_security_groups_ids.each do |sg|
          to_be_unassigned << sg unless sgs.include?(sg)
        end

        begin
          to_be_assigned.each do |sg|
            execute_instance_action('assign_security_group',sg, false)
          end

          to_be_unassigned.each do |sg|
            execute_instance_action('unassign_security_group',sg, false)
          end

          respond_to do |format|
            format.html{redirect_to instances_url}
          end

        rescue => e
          @instance = ServerNG.find(params[:id])
          @instance_security_groups = @instance.security_groups_details
          @instance_security_groups_keys = []
          @instance_security_groups.each do |sg|
            @instance_security_groups_keys << sg.id
          end
          @security_groups = services.networking.security_groups(tenant_id: @scoped_project_id)
          flash.now[:error] = "An error happend while assigning/unassigned security groups to the server. Error: #{e}"
          render action: :edit_securitygroups and return
        end
      end


    end

    private

    def collect_available_ips
      @grouped_fips = {}
      networks = {}
      subnets = {}
      services.networking.project_floating_ips(@scoped_project_id).each do |fip|
        if fip.fixed_ip_address.nil?
          networks[fip.floating_network_id] = services.networking.network(fip.floating_network_id) unless networks[fip.floating_network_id]
          net = networks[fip.floating_network_id]
          unless net.subnets.blank?
            net.subnets.each do |subid|
              subnets[subid] = services.networking.subnet(subid) unless subnets[subid]
              sub = subnets[subid]
              cidr = NetAddr::CIDR.create(sub.cidr)
              if cidr.contains?(fip.floating_ip_address)
                @grouped_fips[sub.name] ||= []
                @grouped_fips[sub.name] << [fip.floating_ip_address, fip.id]
                break
              end
            end
          else
            @grouped_fips[net.name] ||= []
            @grouped_fips[net.name] << [fip.floating_ip_address, fip.id]
          end
        end
      end
    end

    def execute_instance_action(action=action_name,options=nil, with_rendering=true)
      instance_id = params[:id]
      @instance = ServerNG.find(instance_id) rescue nil

      @target_state=nil
      if @instance and (@instance.task_state || '')!='deleting'
        result = options.nil? ? @instance.send(action) : @instance.send(action,options)
        if result
          audit_logger.info(current_user, "has triggered action", action, "on", @instance)
          sleep(2)
          @instance = ServerNG.find(instance_id) rescue nil

          @target_state = target_state_for_action(action)
          @instance.task_state ||= task_state(@target_state) if @instance
        end
      end

      if request.xhr?
        render template: 'compute/instances/update_item.js' if with_rendering
      else
        redirect_to instances_url
      end
    end

    def target_state_for_action(action)
      case action
      when 'start' then Compute::Server::RUNNING
      when 'stop' then Compute::Server::SHUT_DOWN
      when 'shut_off' then Compute::Server::SHUT_OFF
      when 'pause' then Compute::Server::PAUSED
      when 'suspend' then Compute::Server::SUSPENDED
      when 'block' then Compute::Server::BLOCKED
      end
    end

    def task_state(target_state)
      target_state = target_state.to_i if target_state.is_a?(String)
      case target_state
      when Compute::Server::RUNNING then 'starting'
      when Compute::Server::SHUT_DOWN then 'powering-off'
      when Compute::Server::SHUT_OFF then 'powering-off'
      when Compute::Server::PAUSED then 'pausing'
      when Compute::Server::SUSPENDED then 'suspending'
      when Compute::Server::BLOCKED then 'blocking'
      when Compute::Server::BUILDING then 'creating'
      end
    end

    def active_project_id
      unless @active_project_id
        local_project = Project.find_by_domain_fid_and_fid(@scoped_domain_fid,@scoped_project_fid)
        @active_project_id = local_project.key if local_project
      end
      return @active_project_id
    end

    def all_projects
      @all_projects = current_user.is_allowed?('compute:all_projects')
      @admin_option = @all_projects ? { all_tenants: 1 } : {}
    end
  end
end
