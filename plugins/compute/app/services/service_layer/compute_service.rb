module ServiceLayer
  class ComputeService < Core::ServiceLayer::Service
    def driver
      @driver ||= Compute::Driver::Fog.new({
        auth_url:   self.auth_url,
        region:     self.region,
        token:      self.token,
        domain_id:  self.domain_id,
        project_id: self.project_id
      })
    end

    def prepare_filter(query)
      return Excon::Utils.query_string(query: query).sub(/^\?/, '')
    end

    def available?(action_name_sym=nil)
      not current_user.service_url('compute',region: region).nil?
    end

    def find_server(id)
      debug "compute-service -> find_server -> GET /servers/#{id}"
      return nil if id.empty?
      response = api_client.compute.show_server_details(id)
      map_to(Compute::Server,response.body['server'])
    end

    def vnc_console(server_id,console_type='novnc')
      debug "compute-service -> vnc_console -> POST /action"
      response = api_client.compute.get_vnc_console_os_getvncconsole_action(
        server_id,
        "os-getVNCConsole" => {'type' => console_type }
      )
      map_to(Compute::VncConsole,response.body['console'])
    end

    def new_server(params={})
      debug "compute-service -> new_server"
      Compute::Server.new(self,params)
    end

    def create_server(params={})
      debug "compute-service -> create_server -> POST /servers"
      debug params

      name       = params.delete("name")
      flavor_ref = params.delete("flavorRef")
      params["server"] = {
              'flavorRef' => flavor_ref,
              'name'      => name
      }

      image_ref = params.delete("imageRef")
      params['server']['imageRef'] = image_ref if image_ref

      params["max_count"]=params["max_count"].to_i if params["max_count"]
      params["min_count"]=params["min_count"].to_i if params["min_count"]
      if networks=params.delete("networks")
       nics=networks.collect { |n| {'net_id' => n["id"], 'v4_fixed_ip' => n['fixed_ip'], 'port_id' => n['port']} }
       # based on https://github.com/fog/fog-openstack/blob/master/lib/fog/compute/openstack/requests/create_server.rb
       if nics
        params['server']['networks'] =
          Array(nics).map do |nic|
            neti = {}
            neti['uuid']     = (nic['net_id']      || nic[:net_id])      unless (nic['net_id']      || nic[:net_id]).nil?
            neti['fixed_ip'] = (nic['v4_fixed_ip'] || nic[:v4_fixed_ip]) unless (nic['v4_fixed_ip'] || nic[:v4_fixed_ip]).nil?
            neti['port']     = (nic['port_id']     || nic[:port_id])     unless (nic['port_id']     || nic[:port_id]).nil?
            neti
          end
       end
      end

      api_client.compute.create_server(params).body['server']
    end

    def delete_server(server_id)
      debug "compute-service -> delete_server -> DELETE /servers/#{server_id}"
      api_client.compute.delete_server(server_id)
    end

    def servers(filter={})
      debug "compute-service -> servers -> GET servers/detail"
      return [] unless current_user.is_allowed?('compute:instance_list')
      response = api_client.compute.list_servers_detailed(prepare_filter(filter))
      map_to(Compute::Server,response.body['servers'])
    end

    def usage(filter = {})
      debug "compute-service -> usage -> GET /limits"
      response = api_client.compute.show_rate_and_absolute_limits(prepare_filter(filter))
      map_to(Compute::Usage,response.body['limits']['absolute'])
    end

    def rebuild_server(server_id, image_ref, name, admin_pass=nil, metadata=nil, personality=nil)
      debug "compute-service -> rebuild_server -> POST /action"

      # prepare data
      # based on https://github.com/fog/fog-openstack/blob/master/lib/fog/compute/openstack/requests/rebuild_server.rb
      data = {'rebuild' => {
        'imageRef' => image_ref,
        'name'     => name
      }}
      data['rebuild']['adminPass'] = admin_pass if admin_pass
      data['rebuild']['metadata'] = metadata if metadata
      if personality
        body['rebuild']['personality'] = []
        personality.each do |file|
          data['rebuild']['personality'] << {
            'contents' => Base64.encode64(file['contents']),
            'path'     => file['path']
          }
        end
      end

      api_client.compute.rebuild_server_rebuild_action(server_id,data)
    end

    def resize_server(server_id, flavor_ref)
      debug "compute-service -> resize_server -> POST /servers/#{server_id}/action"
      api_client.compute.resize_server_resize_action(server_id, 'resize' => {'flavorRef' => flavor_ref})
    end

    def confirm_resize_server(server_id)
      debug "compute-service -> confirm_resize_server -> POST /servers/#{server_id}/action"
      api_client.compute.confirm_resized_server_confirmresize_action(server_id, 'confirmResize' => nil)
    end

    def revert_resize_server(server_id)
      debug "compute-service -> revert_resize_server -> POST /servers/#{server_id}/action"
      api_client.compute.revert_resized_server_revertresize_action(server_id, 'revertResize' => nil)
    end

    def create_image(server_id, name, metadata={})
      debug "compute-service -> create_image -> POST /action"
      #handle_response { @fog.create_image(server_id, name, metadata).body['image'] }
    end

    def start_server(server_id)
      debug "compute-service -> start_server -> POST /servers/#{server_id}/action"
      api_client.compute.start_server_os_start_action(server_id, 'os-start' => nil)
    end

    def stop_server(server_id)
      debug "compute-service -> stop_server -> POST /servers/#{server_id}/action"
       api_client.compute.stop_server_os_stop_action(server_id, 'os-stop' => nil)
    end

    def reboot_server(server_id, type)
      debug "compute-service -> reboot_server ->  /servers/#{server_id}/action"
      api_client.compute.reboot_server_reboot_action(
        server_id,
        'reboot' => {'type' => type}
      )
    end

    def attach_volume(volume_id, server_id, device)
      debug "compute-service -> attach_volume -> POST /action"
      #handle_response { @fog.attach_volume(volume_id, server_id, device) }
    end

    def detach_volume(server_id, volume_id)
      debug "compute-service -> detach_volume -> POST /action"
      #handle_response { @fog.detach_volume(server_id, volume_id) }
    end

    def suspend_server(server_id)
      debug "compute-service -> suspend_server -> POST /servers/#{server_id}/action"
      api_client.compute.suspend_server_suspend_action(server_id, 'suspend' => nil)
    end

    def pause_server(server_id)
      debug "compute-service -> pause_server -> POST /servers/#{server_id}/action"
      api_client.compute.pause_server_pause_action(server_id, 'pause' => nil)
    end

    def unpause_server(server_id)
      debug "compute-service -> unpause_server -> POST /action"
      api_client.compute.unpause_server_unpause_action(server_id, 'unpause' => nil)
    end

    def reset_server_state(server_id, state)
      debug "compute-service -> reset_server_state -> POST /servers/#{server_id}/action"
      api_client.compute.reset_server_state_os_resetstate_action(server_id, 'os-resetState' => {'state' => state})
    end

    def rescue_server(server_id)
      debug "compute-service -> rescue_server -> POST /servers/#{server_id}/action"
      api_client.compute.rescue_server_rescue_action(server_id, 'rescue' => nil)
    end

    def resume_server(server_id)
      debug "compute-service -> resume_server -> POST /servers/#{server_id}/action"
      api_client.compute.resume_suspended_server_resume_action(server_id, 'resume' => nil)
    end

    def add_fixed_ip(server_id, network_id)
      debug "compute-service -> add_fixed_ip -> POST /action"
      #handle_response{@fog.add_fixed_ip(server_id, network_id)}
    end

    def remove_fixed_ip(server_id, address)
      debug "compute-service -> remove_fixed_ip -> POST /action"
      #handle_response{@fog.remove_fixed_ip(server_id, address)}
    end

    ##################### HYPERVISORS #########################

    def hypervisors(filter = {})
      driver.map_to(Compute::Hypervisor).hypervisors(filter)
    end

    def find_hypervisor(id)
      return nil if id.blank?
      driver.map_to(Compute::Hypervisor).get_hypervisor(id)
    end

    def hypervisor_servers(id)
      driver.map_to(Compute::HypervisorServer).hypervisor_servers(id)
    end

    ##################### SERVICES #########################

    def services(filter = {})
      driver.map_to(Compute::Service).services(filter)
    end

    ##################### HOST AGGREGATES #########################

    def host_aggregates(filter = {})
      driver.map_to(Compute::HostAggregate).host_aggregates(filter)
    end

    def images
      driver.map_to(Compute::Image).images
    end

    def image(id)
      driver.map_to(Compute::Image).get_image(id) rescue nil
    end



    def new_os_interface(server_id,attributes={})
      os_interface = Compute::OsInterface.new(driver,attributes)
      os_interface.server_id = server_id
      os_interface
    end

    def server_os_interfaces(server_id)
      driver.map_to(Compute::OsInterface).list_os_interfaces(server_id)
    end

    def new_flavor(params={})
      Compute::Flavor.new(driver,params)
    end

    def flavor(flavor_id,use_cached = false)
      debug "compute-service -> flavor -> GET /flavors/#{flavor_id}"

      flavor_data = nil
      unless use_cached
        flavor_data = api_client.compute.show_flavor_details(flavor_id).body['flavor']
        Rails.cache.write("server_flavor_#{flavor_id}",flavor_data, expires_in: 24.hours)
      else
        flavor_data = Rails.cache.fetch("server_flavor_#{flavor_id}", expires_in: 24.hours) do
          api_client.compute.show_flavor_details(flavor_id).body['flavor']
        end
      end

      return nil if flavor_data.nil?
      Compute::Flavor.new(self,flavor_data)
    end

    def flavors(filter={})
      debug "compute-service -> flavors -> GET /flavors/detail"
      response = api_client.compute.list_flavors_with_details(prepare_filter(filter))
      map_to(Compute::Flavor, response.body['flavors'])
    end

    def flavor_members(flavor_id)
      driver.map_to(Compute::FlavorAccess).list_flavor_members(flavor_id)
    end

    def flavor_metadata(flavor_id)
      driver.map_to(Compute::FlavorMetadata).get_flavor_metadata(flavor_id)
    end

    def new_flavor_metadata(flavor_id)
      Compute::FlavorMetadata.new(driver, flavor_id: flavor_id)
    end

    def new_flavor_access(params={})
      Compute::FlavorAccess.new(driver,params)
    end

    def availability_zones
      driver.map_to(Compute::AvailabilityZone).availability_zones
    end

    def attach_volume(volume_id, server_id, device)
      driver.attach_volume(volume_id, server_id, device)
    end

    def detach_volume(volume_id, server_id)
      driver.detach_volume(server_id, volume_id)
    end

    ##################### KEYPAIRS #########################
    def new_keypair(attributes={})
      Compute::Keypair.new(driver, attributes)
    end

    def find_keypair(name=nil)
      return nil if name.blank?
      driver.map_to(Compute::Keypair).get_keypair(name)
    end

    def delete_keypair(name=nil)
      return nil if name.blank?
      driver.map_to(Compute::Keypair).delete_keypair(name)
    end

    def keypairs(options={})
      # keypair structure different to others, so manual effort needed
      unless @user_keypairs
        @user_keypairs = []
        keypairs = driver.map_to(Compute::Keypair).keypairs(user_id: @current_user.id)
        keypairs.each do |k|
          kp = Compute::Keypair.new(@driver)
          kp.attributes = k.keypair if k.keypair
          @user_keypairs << kp if kp
        end
      end
      return @user_keypairs
    end



  end
end
