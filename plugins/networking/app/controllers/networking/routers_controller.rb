module Networking
  class RoutersController < DashboardController
    before_filter :fill_available_networks, only: [:new, :create, :edit, :update]

    def index
      @routers = services.networking.routers(tenant_id: @scoped_project_id)

      usage = @routers.length
      @quota_data = services.resource_management.quota_data([
        {service_type: :network, resource_name: :routers, usage: usage}
      ])
    end

    def topology
      @router = services.networking.find_router(params[:router_id])
      @external_network = services.networking.network(@router.external_gateway_info["network_id"])
      @router_interface_ports = services.networking.ports(device_id: @router.id, device_owner: "network:router_interface")

      @topology_graph = {
        name: @router.name,
        type: 'router',
        id: @router.id,
        children: [{name: @external_network.name, type: 'gateway', id: @external_network.id}] + @router_interface_ports.collect do |port|
          node = {name: port.network_object.name, type: 'network', id: port.network_object.id}
          services.networking.ports(network_id: port.network_id).each do |port|
            if port.device_owner.start_with?('compute:')
              node[:children] ||= []
              node[:children] << {name: '', type: 'server', id: port.device_id}
            end
          end
          node
        end
      }
    end

    def node_details
      case params[:type]
      when 'router'
        render partial: 'networking/routers/node_details/router', locals: {router: services.networking.find_router(params[:router_id]) }
      when 'network'
        render partial: 'networking/routers/node_details/network', locals: {network: services.networking.network(params[:id])}
      when 'gateway'
        render partial: 'networking/routers/node_details/gateway', locals: {external_network: services.networking.network(params[:id])}
      when 'server'
        server = ServerNG.find(params[:id]) rescue nil
        port = services.networking.ports(device_id: server.id).first if server
        render partial: 'networking/routers/node_details/server', locals: {server: server, port: port}, status: server.nil? ? 404 : 200
      else
        render text: 'No details available'
      end
    end

    def show
      @router = services.networking.find_router(params[:id])
      @external_network = services.networking.network(@router.external_gateway_info["network_id"])
      @router_interface_ports = services.networking.ports(device_id: @router.id, device_owner: "network:router_interface")
    end

    def new
      @quota_data = services.resource_management.quota_data([
        {service_type: :network, resource_name: :routers}
      ])

      # build new router object (no api call done yet!)
      @router = services.networking.new_router('admin_state_up' => true)
    end

    def create
      # get selected subnets and remove them from params
      @selected_internal_subnets = (params[:router].delete(:internal_subnets) || []).reject(&:empty?)
      # build new router object
      @router = services.networking.new_router(params[:router])
      @router.internal_subnets = @selected_internal_subnets

      if @router.save
        # router is created -> add subnets as interfaces
        services.networking.add_router_interfaces(@router.id, @selected_internal_subnets)
        audit_logger.info(current_user, 'has created', @router)

        flash.now[:notice] = 'Router successfully created.'
        redirect_to plugin('networking').routers_path
      else
        # didn't save -> render new
        render action: :new
      end
    end

    def edit
      @router = services.networking.find_router(params[:id])
      @external_network = services.networking.network(@router.external_gateway_info['network_id'])
      @router_interface_ports = services.networking.ports(device_id: @router.id, device_owner: "network:router_interface")
      @router_internal_subnet_ids =  @router_interface_ports.inject([]) do |array,port|
        (port.fixed_ips || []).each{|fixed_ip| array << fixed_ip["subnet_id"]}
        array
      end
      @router_external_subnet_ids = if @router.external_gateway_info["external_fixed_ips"].nil?
        []
      else
        @router.external_gateway_info["external_fixed_ips"].collect{|data| data['subnet_id']}
      end
    end

    def update
      # get selected subnets and remove them from params
      @selected_internal_subnet_ids = (params[:router].delete(:internal_subnets) || []).reject(&:empty?)

      # build new router object
      @router = services.networking.find_router(params[:id])
      @router.name = params[:router][:name]
      @router.admin_state_up = params[:router][:admin_state_up]

      if params[:router][:external_gateway_info].blank? or params[:router][:external_gateway_info][:network_id].blank?
        @router.external_gateway_info = {}
      else
        @router.external_gateway_info =  params[:router][:external_gateway_info]
      end

      @router.internal_subnets = @selected_internal_subnet_ids

      if @router.save
        attached_ports = services.networking.ports(device_id: @router.id, device_owner: 'network:router_interface')
        @old_selected_internal_subnet_ids = attached_ports.inject([]){|array, port| port.fixed_ips.each{ |ip| array << ip['subnet_id']}; array }

        to_be_detached = (@old_selected_internal_subnet_ids - @selected_internal_subnet_ids)
        to_be_attached = (@selected_internal_subnet_ids - @old_selected_internal_subnet_ids)

        services.networking.remove_router_interfaces(@router.id, to_be_detached)
        services.networking.add_router_interfaces(@router.id, to_be_attached)

        audit_logger.info(current_user, 'has updated', @router)

        flash.now[:notice] = 'Router successfully created.'
        redirect_to plugin('networking').routers_path
      else
        @external_network = services.networking.network(@router.external_gateway_info['network_id'])

        render action: :edit
      end
    end

    def destroy
      @router = services.networking.find_router(params[:id]) rescue nil
      ports = services.networking.ports(device_owner:'network:router_interface',device_id: @router.id)

      @success = false
      if @router
        attached_subnet_ids = (ports || []).inject([]){|array,port| port.fixed_ips.each{|ip| array << ip["subnet_id"]}; array}

        services.networking.remove_router_interfaces(@router.id,attached_subnet_ids)
        if @router.destroy
          @success = true
          audit_logger.info(current_user, "has deleted", @router)
          flash.now[:notice] = "Router successfully deleted."
        else
          flash.now[:error] = @router.errors.full_messages.to_sentence
        end
      end

      respond_to do |format|
        format.js {}
        format.html {redirect_to routers_path}
      end
    end

    protected

    def allowed_networks
      # only cloud admin can cross-assign interfaces
      if current_user.is_allowed?('cloud_network_admin')
        services.networking.networks
      else
        services.networking.project_networks(@scoped_project_id)
      end
    end

    def fill_available_networks
      return if @external_networks && @internal_subnets

      @external_networks = []
      @internal_subnets  = []

      allowed_networks.each do |network|
        if network.external?
          @external_networks << network
        # FIXME: shared networks are not permitted for non cloud admin
        # this is a neutron bug https://bugs.launchpad.net/neutron/+bug/1662477
        # should be just 'else'
        elsif !network.shared?
          network.subnet_objects.each do |subnet|
            subnet.network_name = network.name
            @internal_subnets << subnet
          end
        end
      end
    end
  end
end
