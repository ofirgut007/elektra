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

    # https://github.com/flystack/misty/blob/master/lib/misty/openstack/nova/nova_v2_1.rb
    # https://github.com/fog/fog-openstack/tree/master/lib/fog/compute/openstack/requests

    def prepare_filter(query)
      return Excon::Utils.query_string(query: query).sub(/^\?/, '')
    end

    def available?(action_name_sym=nil)
      not current_user.service_url('compute',region: region).nil?
    end

    def usage(filter = {})
      debug "[compute-service] -> usage -> GET /limits"
      response = api_client.compute.show_rate_and_absolute_limits(prepare_filter(filter))
      map_to(Compute::Usage,response.body['limits']['absolute'])
    end

    ########################### SERVER #############################

    def find_server(id)
      debug "[compute-service] -> find_server -> GET /servers/#{id}"
      return nil if id.empty?
      response = api_client.compute.show_server_details(id)
      map_to(Compute::Server,response.body['server'])
    end

    def new_server(params={})
      # this is used for inital create server dialog
      debug "[compute-service] -> new_server"
      Compute::Server.new(self,params)
    end

    def create_server(params={})
      debug "[compute-service] -> create_server -> POST /servers"
      debug "[compute-service] -> create_server -> Parameter: #{params}"

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
      debug "[compute-service] -> delete_server -> DELETE /servers/#{server_id}"
      api_client.compute.delete_server(server_id)
    end

    def servers(filter={},use_cache = false)
      debug "[compute-service] -> servers -> GET servers/detail"
      return [] unless current_user.is_allowed?('compute:instance_list')

      server_data = nil
      unless use_cache
        server_data = api_client.compute.list_servers_detailed(prepare_filter(filter)).body['servers']
        Rails.cache.write("#{@scoped_project_id}_servers",server_data, expires_in: 2.hours)
      else
        server_data = Rails.cache.fetch("#{@scoped_project_id}_servers", expires_in: 2.hours) do
          api_client.compute.list_servers_detailed(prepare_filter(filter)).body['servers']
        end
      end

       map_to(Compute::Server,server_data)
    end

    def vnc_console(server_id,console_type='novnc')
      debug "[compute-service] -> vnc_console -> POST /action"
      response = api_client.compute.get_vnc_console_os_getvncconsole_action(
        server_id,
        "os-getVNCConsole" => {'type' => console_type }
      )
      map_to(Compute::VncConsole,response.body['console'])
    end

    def rebuild_server(server_id, image_ref, name, admin_pass=nil, metadata=nil, personality=nil)
      debug "[compute-service] -> rebuild_server -> POST /action"

      # prepare data
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
      debug "[compute-service] -> resize_server -> POST /servers/#{server_id}/action"
      api_client.compute.resize_server_resize_action(server_id, 'resize' => {'flavorRef' => flavor_ref})
    end

    def confirm_resize_server(server_id)
      debug "[compute-service] -> confirm_resize_server -> POST /servers/#{server_id}/action"
      api_client.compute.confirm_resized_server_confirmresize_action(server_id, 'confirmResize' => nil)
    end

    def revert_resize_server(server_id)
      debug "[compute-service] -> revert_resize_server -> POST /servers/#{server_id}/action"
      api_client.compute.revert_resized_server_revertresize_action(server_id, 'revertResize' => nil)
    end

    def start_server(server_id)
      debug "[compute-service] -> start_server -> POST /servers/#{server_id}/action"
      api_client.compute.start_server_os_start_action(server_id, 'os-start' => nil)
    end

    def stop_server(server_id)
      debug "[compute-service] -> stop_server -> POST /servers/#{server_id}/action"
       api_client.compute.stop_server_os_stop_action(server_id, 'os-stop' => nil)
    end

    def reboot_server(server_id, type)
      debug "[compute-service] -> reboot_server ->  /servers/#{server_id}/action"
      api_client.compute.reboot_server_reboot_action(
        server_id,
        'reboot' => {'type' => type}
      )
    end

    def suspend_server(server_id)
      debug "[compute-service] -> suspend_server -> POST /servers/#{server_id}/action"
      api_client.compute.suspend_server_suspend_action(server_id, 'suspend' => nil)
    end

    def pause_server(server_id)
      debug "[compute-service] -> pause_server -> POST /servers/#{server_id}/action"
      api_client.compute.pause_server_pause_action(server_id, 'pause' => nil)
    end

    def unpause_server(server_id)
      debug "[compute-service] -> unpause_server -> POST /action"
      api_client.compute.unpause_server_unpause_action(server_id, 'unpause' => nil)
    end

    def reset_server_state(server_id, state)
      debug "[compute-service] -> reset_server_state -> POST /servers/#{server_id}/action"
      api_client.compute.reset_server_state_os_resetstate_action(server_id, 'os-resetState' => {'state' => state})
    end

    def rescue_server(server_id)
      debug "[compute-service] -> rescue_server -> POST /servers/#{server_id}/action"
      api_client.compute.rescue_server_rescue_action(server_id, 'rescue' => nil)
    end

    def resume_server(server_id)
      debug "[compute-service] -> resume_server -> POST /servers/#{server_id}/action"
      api_client.compute.resume_suspended_server_resume_action(server_id, 'resume' => nil)
    end

    ########################### FIXED IP ADDRESS ###################

    # NOTE: not used?
    def add_fixed_ip(server_id, network_id)
      debug "[compute-service] -> add_fixed_ip -> POST /action"
      api_client.compute.add_associate_fixed_ip_addfixedip_action(server_id, 'addFixedIp' => {'networkId' => network_id} )
    end

    # NOTE: not used?
    def remove_fixed_ip(server_id, address)
      debug "[compute-service] -> remove_fixed_ip #{address} -> POST /action"
      api_client.compute.remove_disassociate_fixed_ip_removefixedip_action(server_id, 'removeFixedIp' => {'address' => address} )
    end

    ########################### IMAGES #############################

    def create_image(server_id, name, metadata={})
      # used in create snapshot
      debug "[compute-service] -> create_image #{name} -> POST /action"
      debug "Metadata: #{metadata}"

      api_client.compute.create_image_createimage_action(
        server_id,
        'createImage' => {
          'name'     => name,
          'metadata' => metadata
      })
    end

    def images
      debug "[compute-service] -> images -> GET /images"
      response = api_client.compute.list_images()
      map_to(Compute::Image,response.body['images'])
    end

    def image(image_id,use_cache = false)
      debug "[compute-service] -> image -> GET /images/#{image_id}"

      image_data = nil
      unless use_cache
        image_data = api_client.compute.show_image_details(image_id).body['image']
        Rails.cache.write("server_image_#{image_id}", image_data, expires_in: 24.hours)
      else
        image_data = Rails.cache.fetch("server_image_#{image_id}", expires_in: 24.hours) do
          api_client.compute.show_image_details(image_id).body['image']
        end
      end

      return nil if image_data.nil?
      map_to(Compute::Image image_data)
    end

    # NOTE: not used?
    def delete_image(image_id)
      debug "[compute-service] -> images -> DELETE /images/#{image_id}"
      api_client.compute.delete_image(image_id)
    end

    ########################### VOLUMES #############################

    def attach_volume(volume_id, server_id, device)
      debug "[compute-service] -> attach_volume #{volume_id} -> POST /action"
      api_client.compute.attach_a_volume_to_an_instance(
        server_id,
        'volumeAttachment' => {
        'volumeId' => volume_id.to_s,
        'device'   => device
      })
    end

    def detach_volume(volume_id, server_id)
      debug "[compute-service] -> detach_volume #{volume_id} -> DELETE /action"
      api_client.compute.detach_a_volume_from_an_instance(server_id,volume_id)
    end

    def volumes(server_id,filter={})
      debug "[compute-service] -> volumes -> GET /os-volumes"
      response = api_client.compute.list_volumes(prepare_filter(filter))
      response.body['volumes'].select{|vol|
        vol["attachments"].find { |attachment| attachment["serverId"] == server_id or attachment["server_id"] == server_id}
      }.collect{|v| map_to(Compute::OsVolume,v)}
    end

    # NOTE: not used?
    def get_volume(id)
      debug "[compute-service] -> get_volume -> GET /os-volumes/#{id}"
      response = api_client.compute.show_volume_details(id)
      map_to(Compute::OsVolume,response.body['volume'])
    end

    # NOTE: not used?
    def delete_volume(id)
      debug "[compute-service] -> delete_volume -> DELETE /os-volumes/#{id}"
      api_client.compute.delete_volume(id)
    end

    # NOTE: not used?
    def create_volume(params={})
      debug "[compute-service] -> create_volume -> POST /os-volumes"
      debug "[compute-service] -> create_volume -> Parameter: #{params}"
      api_client.compute.create_volume(params).body['volume']
    end

    ##################### HYPERVISORS #########################

    def hypervisors(filter = {})
      debug "[compute-service] -> hypervisors -> GET /os-hypervisors/detail"
      response = api_client.compute.list_hypervisors_details(prepare_filter(filter))
      map_to(Compute::Hypervisor,response.body['hypervisors'])
    end

    def find_hypervisor(id)
      debug "[compute-service] -> find_hypervisor -> GET /os-hypervisors/#{id}"
      return nil if id.blank?
      response = api_client.compute.show_hypervisor_details(id)
      map_to(Compute::Hypervisor,response.body['hypervisor'])
    end

    def hypervisor_servers(hypervisor_hostname_pattern)
      debug "[compute-service] -> hypervisor_servers -> GET /os-hypervisors/#{hypervisor_hostname_pattern}/servers"
      response = api_client.compute.list_hypervisor_servers(hypervisor_hostname_pattern)
      map_to(Compute::HypervisorServer,response.body['hypervisors'].first['servers'])
    end

    ##################### SERVICES #########################

    def services(filter = {})
      debug "[compute-service] -> services -> GET /os-services"
      response = api_client.compute.list_compute_services(prepare_filter(filter))
      map_to(Compute::Service,response.body['services'])
    end

    def disable_service_reason(host, name, disabled_reason)
      debug "[compute-service] -> disable_service_reason -> PUT /os-services/disable-log-reason"
      api_client.compute.log_disabled_compute_service_information(
        "host"            => host,
        "binary"          => name, # I have no idea why that is called binary but name is better
        "disabled_reason" => disabled_reason
      )
    end

    def disable_service(host, name)
      debug "[compute-service] -> disable_service -> PUT /os-services/disable"
      api_client.compute.disable_scheduling_for_a_compute_service(
        "host"   => host,
        "binary" => name # I have no idea why that is called binary but name is better
      )
    end

    def enable_service(host, name)
      debug "[compute-service] -> enable_service -> PUT /os-services/enable"
      api_client.compute.enable_scheduling_for_a_compute_service(
        "host"   => host,
        "binary" => name # I have no idea why that is called binary but name is better
      )
    end

    ##################### HOST AGGREGATES #########################

    def host_aggregates(filter = {})
      debug "[compute-service] -> host_aggregates -> GET /os-aggregates"
      response = api_client.compute.list_aggregates(prepare_filter(filter))
      map_to(Compute::HostAggregate, response.body['aggregates'])
    end

    ############################# OS INTERFACES ##############################

    def new_os_interface(server_id,attributes={})
      debug "[compute-service] -> new_os_interface"
      os_interface = Compute::OsInterface.new(self,attributes)
      os_interface.server_id = server_id
      os_interface
    end

    def create_os_interface(server_id,options={})
      debug "[compute-service] -> create_os_interface -> POST /servers/#{server_id}/os-interface"

      data = {
        'interfaceAttachment' => {}
      }
      if options[:port_id]
        data['interfaceAttachment']['port_id'] = options[:port_id]
      elsif options[:net_id]
        data['interfaceAttachment']['net_id'] = options[:net_id]
      end

      if options[:ip_address]
        data['interfaceAttachment']['fixed_ips'] = {ip_address: options[:ip_address]}
      end

      api_client.compute.create_interface(server_id,data)

    end

    def delete_os_interface(server_id,port_id)
      debug "[compute-service] -> delete_os_interface -> DELETE /servers/#{server_id}/os-interface/#{port_id}"
      api_client.compute.detach_interface(server_id,port_id)
    end

    def server_os_interfaces(server_id)
      debug "[compute-service] -> server_os_interfaces -> GET /servers/#{server_id}/os-interface"
      response = api_client.compute.list_port_interfaces(server_id)
      map_to(Compute::OsInterface,response.body['interfaceAttachments'])
    end

    ########################### SECURITY_GROUPS #############################

    def security_groups_details(server_id)
      debug "[compute-service] -> security_groups_details -> GET /servers/#{server_id}/os-security-groups"
      response = api_client.compute.list_security_groups_by_server(server_id)
      map_to(Networking::SecurityGroup,response.body['security_groups'])
    end

    def remove_security_group(server_id, sg_id)
      debug "[compute-service] -> remove_security_group -> POST /servers/#{server_id}/action"
      api_client.compute.remove_security_group_from_a_server_removesecuritygroup_action(
        server_id,
        'removeSecurityGroup' => {"name" => sg_id}
      )
    end

    def add_security_group(server_id, sg_id)
      debug "[compute-service] -> add_security_group -> POST /servers/#{server_id}/action"
      api_client.compute.add_security_group_to_a_server_addsecuritygroup_action(
        server_id,
        'addSecurityGroup' => {"name" => sg_id}
      )
    end

    ########################### FLAVORS #############################

    def new_flavor(params={})
      # this is used for inital create flavor dialog
      debug "[compute-service] -> new_flavor"
      Compute::Flavor.new(self,params)
    end

    def create_flavor(attributes)
      debug "[compute-service] -> create_flavor -> POST /flavors"
      debug "[compute-service] -> create_flavor -> Parameter: #{attributes}"

      api_client.compute.create_flavor(
        'flavor' => {
                      'name'                       => attributes[:name],
                      'ram'                        => attributes[:ram],
                      'vcpus'                      => attributes[:vcpus],
                      'disk'                       => attributes[:disk],
                      'id'                         => attributes[:flavor_id],
                      'swap'                       => attributes[:swap],
                      'OS-FLV-EXT-DATA:ephemeral'  => attributes[:ephemeral],
                      'os-flavor-access:is_public' => attributes[:is_public],
                      'rxtx_factor'                => attributes[:rxtx_factor]
        }
      ).body['flavor']
    end

    def delete_flavor(id)
      debug "[compute-service] -> delete_flavor -> DELETE /flavors/#{id}"
      api_client.compute.delete_flavor(id)
    end

    def flavor(flavor_id,use_cache = false)
      debug "[compute-service] -> flavor -> GET /flavors/#{flavor_id}"

      flavor_data = nil
      unless use_cache
        flavor_data = api_client.compute.show_flavor_details(flavor_id).body['flavor']
        Rails.cache.write("server_flavor_#{flavor_id}",flavor_data, expires_in: 24.hours)
      else
        flavor_data = Rails.cache.fetch("server_flavor_#{flavor_id}", expires_in: 24.hours) do
          api_client.compute.show_flavor_details(flavor_id).body['flavor']
        end
      end

      return nil if flavor_data.nil?
      map_to(Compute::Flavor,flavor_data)
    end

    def flavors(filter={})
      debug "[compute-service] -> flavors -> GET /flavors/detail"
      response = api_client.compute.list_flavors_with_details(prepare_filter(filter))
      map_to(Compute::Flavor, response.body['flavors'])
    end

    def add_flavor_access_to_tenant(flavor_id,tenant_id)
      debug "[compute-service] -> add_flavor_access_to_tenant -> POST /flavors/#{flavor_id}/action"
      api_client.compute.add_flavor_access_to_tenant_addtenantaccess_action(
        flavor_id,
        "addTenantAccess" => { "tenant" => tenant_id}
      )
    end

    def remove_flavor_access_from_tenant(flavor_id,tenant_id)
      debug "[compute-service] -> remove_flavor_access_from_tenant -> POST /flavors/#{flavor_id}/action"
       api_client.compute.remove_flavor_access_from_tenant_removetenantaccess_action(
        flavor_id,
        "removeTenantAccess" => { "tenant" => tenant_id.to_s }
      )
    end

    def create_flavor_metadata(flavor_id,flavor_extras)
      debug "[compute-service] -> create_flavor_metadata -> POST /flavors/#{flavor_id}/os-extra_specs"
      response = api_client.compute.create_extra_specs_for_a_flavor(flavor_id, 'extra_specs' => flavor_extras)
      map_to(Compute::FlavorMetadata,response.body['extra_specs'])
    end

    def delete_flavor_metadata(flavor_id,key)
      debug "[compute-service] -> delete_flavor_metadata -> DELETE /flavors/#{flavor_id}/os-extra_specs/#{key}"
      api_client.compute.delete_an_extra_spec_for_a_flavor(flavor_id, key)
    end

    def flavor_members(flavor_id)
      debug "[compute-service] -> flavor_members -> GET /flavors/#{flavor_id}/os-flavor-access"
      response = api_client.compute.list_flavor_access_information_for_given_flavor(flavor_id)
      map_to(Compute::FlavorAccess,response.body['flavor_access'])
    end

    def flavor_metadata(flavor_id)
      debug "[compute-service] -> flavor_metadata -> GET /flavors/#{flavor_id}/os-extra_specs"
      response = api_client.compute.list_extra_specs_for_a_flavor(flavor_id)
      map_to(Compute::FlavorMetadata,response.body['extra_specs'])
    end

    def new_flavor_metadata(flavor_id)
      debug "[compute-service] -> new_flavor_metadata"
      Compute::FlavorMetadata.new(self, flavor_id: flavor_id)
    end

    def new_flavor_access(params={})
      debug "[compute-service] -> new_flavor_access"
      Compute::FlavorAccess.new(self,params)
    end

    ########################### AVAILABILITY_ZONES #############################

    def availability_zones
      debug "[compute-service] -> availability_zones -> GET /os-availability-zone"
      response = api_client.compute.get_availability_zone_information()
      map_to(Compute::AvailabilityZone,response.body['availabilityZoneInfo'])
    end

    ##################### KEYPAIRS #########################

    def new_keypair(attributes={})
      debug "[compute-service] -> new_keypair"
      Compute::Keypair.new(driver, attributes)
    end

    def find_keypair(name=nil)
      debug "[compute-service] -> find_keypair"
      return nil if name.blank?
      driver.map_to(Compute::Keypair).get_keypair(name)
    end

    def delete_keypair(name=nil)
      debug "[compute-service] -> delete_keypair"
      return nil if name.blank?
      driver.map_to(Compute::Keypair).delete_keypair(name)
    end

    def keypairs(options={})
      debug "[compute-service] -> keypairs"
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
