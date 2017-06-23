require 'ipaddr'

module Networking
  class FloatingIp < Core::ServiceLayer::Model
    def attributes_for_create
      {
        'floating_network_id' => read('floating_network_id'),
        'description'         => read('description'),
        'subnet_id'           => read('floating_subnet_id')
      }.delete_if { |_k, v| v.blank? }
    end

    def attributes_for_update
      {
        'description' => read('description'),
        'port_id'     => read('port_id')
      }.delete_if { |_k, v| v.blank? }
    end

    def subnet_object
      @subnet_object if @subnet_object

      subnets = Rails.cache.fetch("network_#{floating_network_id}_subnets", expires_in: 1.hours) do
        @driver.map_to(Networking::Subnet).subnets(network_id: floating_network_id)
      end || []

      @subnet_object = subnets.find { |subnet| IPAddr.new(subnet.cidr).include?(floating_ip_address) }
    end
  end
end
