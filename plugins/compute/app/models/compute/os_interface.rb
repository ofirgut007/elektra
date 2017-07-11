module Compute
  class OsInterface < Core::ServiceLayerNg::Model
    # overwrite standard attributes_for_create from model.rb
    # take a look to perform_create on model.rb
    def attributes_for_create
      {
        :fixed_ips   => read("fixed_ips"),
        :net_id      => read("net_id"),
        :port_id     => read("port_id")
      }.delete_if { |k, v| v.blank? }
    end

    # overwrite default perform_service_create method from model.rb
    def perform_service_create(create_attributes)
      @service.create_os_interface(server_id, create_attributes)
    end
    # overwrite default perform_service_delete method from model.rb
    def perform_service_delete(id)
      @service.delete_os_interface(server_id, port_id)
    end
  end
end
