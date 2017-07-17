# frozen_string_literal: true

module Networking
  # Implements Network actions
  class NetworksController < DashboardController
    before_filter :load_type, except: [:subnets]

    def index
      filter_options = {
        'router:external' => @network_type == 'external',
        sort_key: 'name'
      }
      @networks = paginatable(per_page: 15) do |pagination_options|
        services_ng.networking.networks(filter_options.merge(pagination_options))
      end

      # all owned networks + subnets without pagination + filtering
      usage_networks = services_ng.networking.networks.select do |n|
        n.tenant_id == @scoped_project_id
      end.length

      usage_subnets = services_ng.networking.subnets.select do |s|
        s.tenant_id == @scoped_project_id
      end.length

      @quota_data = services_ng.resource_management.quota_data(
          current_user.domain_id || current_user.project_domain_id,
          current_user.project_id,[
            { service_type: :network, resource_name: :networks, usage: usage_networks },
            { service_type: :network, resource_name: :subnets, usage: usage_subnets }
          ]
      )
    end

    def show
      @network = services_ng.networking.find_network(params[:id])
      @subnets = services_ng.networking.subnets(network_id: @network.id)
      @ports   = services_ng.networking.ports(network_id: @network.id)
    end

    def new
      @network = services_ng.networking.new_network(
        name: "#{@scoped_project_name}_#{@network_type}"
      )
      @subnet = services_ng.networking.new_subnet(
        name: "#{@network.name}_sub", enable_dhcp: true
      )
    end

    def create
      network_params = params[:network]
      subnets_params = network_params.delete(:subnets)
      @network = services_ng.networking.new_network(network_params)
      @errors = Array.new

      if @network.save
        if subnets_params.present?
          @subnet = services_ng.networking.new_subnet(subnets_params)
          @subnet.network_id = @network.id

          # FIXME: anti-pattern of doing two things in one action
          if @subnet.save
            flash[:keep_notice_htmlsafe] = "Network #{@subnet.name} successfully created.<br /> <strong>Please note:</strong> If you want to attach floating IPs to objects in this network you will need to #{view_context.link_to('create a router', plugin('networking').routers_path)} connecting this network to the floating IP network."
            audit_logger.info(current_user, 'has created', @network)
            audit_logger.info(current_user, 'has created', @subnet)
            redirect_to plugin('networking').send("networks_#{@network_type}_index_path")
          else
            @network.destroy
            @errors = @subnet.errors
            render action: :new
          end
        else
          audit_logger.info(current_user, 'has created', @network)
          redirect_to plugin('networking').send("networks_#{@network_type}_index_path")
        end

      else
        @errors = @network.errors
        render action: :new
      end
    end

    def edit
      @network = services_ng.networking.find_network(params[:id])
    end

    def update
      @network = services_ng.networking.new_network(params[:network])
      @network.id = params[:id]

      if @network.save
        flash[:notice] = 'Network successfully updated.'
        audit_logger.info(current_user, 'has updated', @network)
        redirect_to plugin('networking').send("networks_#{@network_type}_index_path")
      else
        render action: :edit
      end
    end

    def destroy
      @network = services_ng.networking.new_network
      @network.id = params[:id]

      if @network
        if @network.destroy
          audit_logger.info(current_user, 'has deleted', @network)
          flash[:notice] = 'Network successfully deleted.'
        else
          flash[:error] = @network.errors.full_messages.to_sentence
        end
      end

      respond_to do |format|
        format.js {}
        format.html { redirect_to plugin('networking').send("networks_#{@network_type}_index_path") }
      end
    end

    def subnets
      availability = cloud_admin.networking.network_ip_availability(params[:network_id]) rescue nil
      # subnets = services_ng.networking.subnets(network_id: params[:network_id])
      #render json: services_ng.networking.subnets(network_id: params[:network_id])
      render json: availability.nil? ? [] : availability.subnet_ip_availability
    end

    private

    def load_type
      raise 'has to be implemented in subclass'
    end
  end
end
