# frozen_string_literal: true

module Networking
  # Implements FloatingIp actions
  class FloatingIpsController < DashboardController
    # set policy context
    authorization_context 'networking'
    # enforce permission checks. This will automatically
    # investigate the rule name.
    authorization_required

    def index
      per_page = params[:per_page] || 20
      @floating_ips = paginatable(per_page: per_page) do |pagination_options|
        services_ng.networking.project_floating_ips(
          @scoped_project_id,
          pagination_options.merge(
            sort_key: [:floating_ip_address], sort_dir: [:desc]
          )
        )
      end
      @quota_data = services_ng.resource_management.quota_data(
          current_user.domain_id || current_user.project_domain_id,
          current_user.project_id,[
            { service_type: :network, resource_name: :floating_ips, usage: @floating_ips.length }
          ]
      )

      # this is relevant in case an ajax paginate call is made.
      # in this case we don't render the layout, only the list!
      if request.xhr?
        render partial: 'list', locals: { floating_ips: @floating_ips }
      else
        # comon case, render index page with layout
        render action: :index
      end
    end

    def show
      @floating_ip = services_ng.networking.find_floating_ip(params[:id])
      @port = services_ng.networking.find_port(@floating_ip.port_id)
      @network = services_ng.networking.find_network(@floating_ip.floating_network_id)
    end

    def new
      @floating_networks = services_ng.networking.networks(
        'router:external' => true
      )
      @floating_ip = services_ng.networking.new_floating_ip
      return unless @floating_networks.length == 1
      @floating_ip.floating_network_id = @floating_networks.first.id
    end

    def create
      @floating_networks = services_ng.networking.networks(
        'router:external' => true
      )
      @floating_ip = services_ng.networking.new_floating_ip(params[:floating_ip])
      @floating_ip.tenant_id = @scoped_project_id

      if @floating_ip.save
        audit_logger.info(current_user, 'has created', @floating_ip)
        render action: :create
      else
        render action: :new
      end
    end

    def destroy
      @floating_ip = services_ng.networking.new_floating_ip
      @floating_ip.id = params[:id]

      if @floating_ip.destroy
        @deleted = true
        audit_logger.info(current_user, 'has deleted floating ip', params[:id])
        flash.now[:notice] = 'Floating IP deleted!'
      else
        @deleted = false
        flash.now[:error] = 'Could not delete floating IP.'
      end
    end
  end
end
