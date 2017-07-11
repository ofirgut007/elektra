module ServiceLayerNg
  # This module implements Openstack Domain API
  module OsInterface

    def new_os_interface(server_id,params = {})
      debug "[compute-service][OsInterface] -> new_os_interface"
      debug "[compute-service][OsInterface] -> new_os_interface -> Parameter: #{params}"
      
      os_interface = Compute::OsInterface.new(self,params)
      # the server_id is needed to bind the interface on the related server
      # take a look to innstances_controller create_interface()
      os_interface.server_id = server_id
      os_interface
    end

    # this is a special case and called from OsInterface model perform_create()
    def create_os_interface(server_id, params)
      debug "[compute-service][OsInterface] -> create_os_interface -> POST /servers/#{server_id}/os-interface"
      debug "[compute-service][OsInterface] -> create_os_interface -> Parameter: #{params}"

      data = {
        'interfaceAttachment' => {}
      }
      if params[:port_id]
        data['interfaceAttachment']['port_id'] = params[:port_id]
      elsif params[:net_id]
        data['interfaceAttachment']['net_id'] = params[:net_id]
      end

      if params[:fixed_ips]
        data['interfaceAttachment']['fixed_ips'] = {ip_address: params[:fixed_ips]}
      end

      api.compute.create_interface(server_id,data).data
    end

    def delete_os_interface(server_id,port_id)
      debug "[compute-service][OsInterface] -> delete_os_interface -> DELETE /servers/#{server_id}/os-interface/#{port_id}"
      api.compute.detach_interface(server_id,port_id)
    end

    def server_os_interfaces(server_id)
      debug "[compute-service][OsInterface] -> server_os_interfaces -> GET /servers/#{server_id}/os-interface"
      api.compute.list_port_interfaces(server_id).map_to(Compute::OsInterface)
    end

  end
end