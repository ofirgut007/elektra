module Loadbalancing
  class LoadbalancersController < ::Loadbalancing::ApplicationController
    # set policy context
    authorization_context 'loadbalancing'
    # enforce permission checks. This will automatically investigate the rule name.
    authorization_required except: [:new_floatingip, :attach_floatingip, :detach_floatingip, :update_item, :get_item]

    def index
      @loadbalancers = services.loadbalancing.loadbalancers(tenant_id: @scoped_project_id)
      @fips = services_ng.networking.project_floating_ips(@scoped_project_id)

      @private_networks = services_ng.networking.project_networks(@scoped_project_id).delete_if { |n| n.attributes["router:external"]==true } if services_ng.networking.available?
      @subnets = {}
      @private_networks.each do |pn|
        unless pn.subnets.blank?
          pn.subnets.each do |subid|
            @subnets[subid] = services_ng.networking.find_subnet(subid) unless @subnets[subid]
          end
        end
      end

      @loadbalancers.each do |lb|
        @fips.each do |fip|
          lb.floating_ip = lb.vip_port_id == fip.port_id ? fip : nil
          break if lb.floating_ip
        end
        @subnets.each do |id, sub|
          cidr = NetAddr::CIDR.create(sub.cidr)
          if cidr.contains?(lb.vip_address)
            lb.subnet = sub
            break
          end
        end
      end

      @quota_data = services_ng.resource_management.quota_data(
            current_user.domain_id || current_user.project_domain_id,
            current_user.project_id,[
              { service_type: :network, resource_name: :loadbalancers, usage: @loadbalancers.length },
            ])
    end

    def show
      @loadbalancer = services.loadbalancing.find_loadbalancer(params[:id])
      statuses = services.loadbalancing.loadbalancer_statuses(params[:id])
      @statuses = statuses.state
    end

=begin
    def update_statuses
      begin
        @statuses = services.loadbalancing.loadbalancer_statuses(params[:id])
        if @statuses
          render json: @statuses
        else
          render json: {}
        end
      rescue => e
        render json: {}
      end
    end
=end

    # Get statuses object for one loadbalancer
    def update_status
      begin
        @states = services.loadbalancing.loadbalancer_statuses(params[:id])
      end
    end

    # get statuses for all loadbalancers in project (for index)
    def update_all_status
      begin
        @loadbalancers = services.loadbalancing.loadbalancers(tenant_id: @scoped_project_id)
        @states = []
        @loadbalancers.each do |lb|
          @states << services.loadbalancing.loadbalancer_statuses(lb.id)
        end
        @states
      end
    end

    def new
      @loadbalancer = services.loadbalancing.new_loadbalancer
      @private_networks = services_ng.networking.project_networks(@scoped_project_id).delete_if { |n| n.attributes["router:external"]==true } if services_ng.networking.available?
    end

    def create
      @loadbalancer = services.loadbalancing.new_loadbalancer()
      @loadbalancer.attributes = loadbalancer_params.delete_if { |key, value| value.blank? }

      if @loadbalancer.save
        audit_logger.info(current_user, "has created", @loadbalancer)
        render template: 'loadbalancing/loadbalancers/create.js'
        #redirect_to loadbalancers_path, notice: 'Load Balancer successfully created.'
      else
        @private_networks = services_ng.networking.project_networks(@scoped_project_id).delete_if { |n| n.attributes["router:external"]==true } if services_ng.networking.available?
        render :new
      end

      @attributes    end

    def edit
      @loadbalancer = services.loadbalancing.find_loadbalancer(params[:id])
      @private_networks = services_ng.networking.project_networks(@scoped_project_id).delete_if { |n| n.attributes["router:external"]==true } if services_ng.networking.available?
    end

    def update
      @loadbalancer = services.loadbalancing.find_loadbalancer(params[:id])
      @loadbalancer.name = loadbalancer_params[:name]
      @loadbalancer.description = loadbalancer_params[:description]
      if @loadbalancer.save
        audit_logger.info(current_user, "has updated", @loadbalancer)
        redirect_to loadbalancers_path(), notice: 'Load Balancer was successfully updated.'
      else
        render :edit
      end
    end

    def destroy
      @loadbalancer = services.loadbalancing.find_loadbalancer(params[:id])
      if @loadbalancer.destroy
        @loadbalancer.provisioning_status = "PENDING_DELETE"
        audit_logger.info(current_user, "has deleted", @loadbalancer)
        flash.now[:error] = "Load Balancer will be deleted."
        render template: 'loadbalancing/loadbalancers/destroy_item.js'
      else
        flash.now[:error] = "Load Balancer deletion failed."
        redirect_to loadbalancers_path
      end
    end

    def new_floatingip
      @loadbalancer = services.loadbalancing.find_loadbalancer(params[:id])
      collect_available_ips
      @floating_ip = Networking::FloatingIp.new(nil)
    end

    def attach_floatingip

      enforce_permissions("loadbalancing:loadbalancer_assign_ip")

      @loadbalancer = services.loadbalancing.find_loadbalancer(params[:id])
      vip_port_id = @loadbalancer.vip_port_id
      @floating_ip = Networking::FloatingIp.new(nil, params[:floating_ip])

      success = begin
        @floating_ip = services_ng.networking.attach_floatingip(params[:floating_ip][:ip_id], vip_port_id)
        if @floating_ip.port_id
          true
        else
          false
        end
      rescue => e
        if e.type == 'NotFound'
          @floating_ip.errors.add('Error:', 'Could not attach floating IP to load balancer. Please verify that a router between private and floating ip network exists.')
        else
          @floating_ip.errors.add('message', e.message)
        end
        false
      end

      if success
        audit_logger.info(current_user, "has attached", @floating_ip, "to loadbalancer", params[:id])

        respond_to do |format|
          format.html { redirect_to loadbalancers_url }
          format.js {
            @loadbalancer.floating_ip = @floating_ip
          }
        end
      else
        collect_available_ips
        render action: :new_floatingip
      end
    end

    def detach_floatingip
      enforce_permissions("loadbalancing:loadbalancer_assign_ip")
      begin
        @floating_ip = services_ng.networking.detach_floatingip(params[:floating_ip_id])
      rescue => e
        flash.now[:error] = "Could not detach Floating IP. Error: #{e.message}"
      end

      respond_to do |format|
        format.html {
          sleep(3)
          redirect_to loadbalancers_url
        }
        format.js {
          if @floating_ip and @floating_ip.port_id.nil?
            @loadbalancer = services.loadbalancing.find_loadbalancer(params[:id])
            @loadbalancer.floating_ip = nil
          end
        }
      end
    end

    # update instance table row (ajax call)
    def update_item
      begin
        @loadbalancer = services.loadbalancing.find_loadbalancer(params[:id])
        @fips = services_ng.networking.project_floating_ips(@scoped_project_id)
        @fips.each do |fip|
          @loadbalancer.floating_ip = @loadbalancer.vip_port_id == fip.port_id ? fip : nil
          break if @loadbalancer.floating_ip
        end

        respond_to do |format|
          format.js do
            @loadbalancer if @loadbalancer
          end
        end
      rescue => e
        return nil
      end
    end

    # used for polling state information
    def get_item
      begin
        @loadbalancer = services.loadbalancing.find_loadbalancer(params[:id])
        #puts ">>>>>>>>>>>>>>>>>>>>>>>>>>   #{ @loadbalancer.provisioning_status}   <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<"
        render json: {provisioning_status: @loadbalancer.provisioning_status}
      rescue => e
        render json: {provisioning_status: 'UNKNOWN'}
      end
    end


    private

    def collect_available_ips
      @grouped_fips = {}
      networks = {}
      subnets = {}
      services_ng.networking.project_floating_ips(@scoped_project_id).each do |fip|
        if fip.fixed_ip_address.nil?
          networks[fip.floating_network_id] = services_ng.networking.find_network(fip.floating_network_id) unless networks[fip.floating_network_id]
          net = networks[fip.floating_network_id]
          unless net.subnets.blank?
            net.subnets.each do |subid|
              subnets[subid] = services_ng.networking.find_subnet(subid) unless subnets[subid]
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
      return
    end

    def loadbalancer_params
      return params[:loadbalancer].merge(tenant_id: @scoped_project_id)
    end

  end
end
