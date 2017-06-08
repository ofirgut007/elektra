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
      puts "compute-service -> find server"
      return nil if id.empty?
      response = api_client.compute.show_server_details(id)
      map_to(Compute::Server,response.body['server'])
    end

    def vnc_console(server_id,console_type='novnc')
      puts "compute-service -> vnc console"
      response = api_client.compute.get_vnc_console_os_getvncconsole_action(
        server_id,
        "os-getVNCConsole" => {'type' => console_type }
      )
      map_to(Compute::VncConsole,response.body['console'])
    end

    def new_server(params={})
      puts "compute-service -> new server model"
      Compute::Server.new(self,params)
    end

    def create_server(params={})
      puts "compute-service -> create server"
      pp params

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
       # ripped from https://github.com/fog/fog-openstack/blob/master/lib/fog/compute/openstack/requests/create_server.rb#L45-L54
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
      puts "compute-service -> delete server"
      api_client.compute.delete_server(server_id)
    end

    def servers(filter={})
      puts "compute-service -> servers"
      return [] unless current_user.is_allowed?('compute:instance_list')
      response = api_client.compute.list_servers_detailed(prepare_filter(filter))
      map_to(Compute::Server,response.body['servers'])
    end

    def usage(filter = {})
      puts "compute-service -> usage"
      response = api_client.compute.show_rate_and_absolute_limits(prepare_filter(filter))
      map_to(Compute::Usage,response.body['limits']['absolute'])
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

    def flavors(filter={})
      driver.map_to(Compute::Flavor).flavors(filter)
    end

    def flavor(id)
      driver.map_to(Compute::Flavor).get_flavor(id)
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

    def resize_server(server_id,flavor_id)
      driver.resize_server(server_id, flavor_id)
    end

    def confirm_resize_server(server_id)
      driver.confirm_resize_server(server_id)
    end

    def revert_resize_server(server_id)
      driver.revert_resize_server(server_id)
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
