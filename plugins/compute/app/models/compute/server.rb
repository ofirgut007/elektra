require "base64"

module Compute
  class Server < Core::ServiceLayerNg::Model
    validates :name, presence: {message: 'Please provide a name'}
    validates :image_id, presence: {message: 'Please select an image'}
    validates :flavor_id, presence: {message: 'Please select a flavor'}
    validates :network_ids, presence: {message: 'Please select at least one network'}
    validates :keypair_id, presence: {message: "Please choose a keypair for us to provision to the server. Otherwise you will not be able to log in."}

    NO_STATE    = 0
    RUNNING     = 1
    BLOCKED     = 2
    PAUSED      = 3
    SHUT_DOWN   = 4
    SHUT_OFF    = 5
    CRASHED     = 6
    SUSPENDED   = 7
    FAILED      = 8
    BUILDING    = 9

    def power_state_string
      case self.power_state
      when RUNNING then "Running"
      when BLOCKED then "Blocked"
      when PAUSED then "Paused"
      when SHUT_DOWN then "Shut down"
      when SHUT_OFF then "Shut off"
      when CRASHED then "Crashed"
      when SUSPENDED then "Suspended"
      when FAILED then "Failed"
      when BUILDING then "Building"
      else
        'No State'
      end
    end


    def attributes_for_create
      {
        "name"              => read("name"),
        "imageRef"          => read("image_id"),
        "flavorRef"         => read("flavor_id"),
        "max_count"         => read("max_count"),
        "min_count"         => read("min_count"),
        # Optional
        "networks"          => read("network_ids"),
        "security_groups"   => read("security_groups"),
        "availability_zone" => read("availability_zone_id"),
        "key_name"          => read("keypair_id"),
        "user_data"         => Base64.encode64(read("user_data"))
        }.delete_if { |k, v| v.blank? }
    end
    
    def self.prepare_filter(query)
      return Excon::Utils.query_string(query: query).sub(/^\?/, '')
    end

    def security_groups
      read("security_groups") || []
    end

    def security_groups_details
      @service.security_groups_details self.id
    end

    def availability_zone
      read("OS-EXT-AZ:availability_zone")
    end

    def power_state
      read("OS-EXT-STS:power_state")
    end

    def vm_state
      read("OS-EXT-STS:vm_state")
    end

    def attr_host
      read("OS-EXT-SRV-ATTR:host")
    end

    def volumes_attached
      read("os-extended-volumes:volumes_attached")
    end

    def task_state
      task_state = read("OS-EXT-STS:task_state")
      return nil if task_state.nil? or task_state.empty? or task_state.downcase=='none'
      return task_state
    end

    # borrowed from fog
    def ip_addresses
      addresses ? addresses.values.flatten.map{|x| x['addr']} : []
    end

    def floating_ips
      @floating_ips ||= addresses.values.flatten.select do |ip|
        ip["OS-EXT-IPS:type"]=="floating"
      end
    end

    # borrowed from fog
    def floating_ip_addresses
      all_floating= addresses ? addresses.values.flatten.select{ |data| data["OS-EXT-IPS:type"]=="floating" }.map{|addr| addr["addr"] } : []
      return [] if all_floating.empty?
      # Return them all, leading with manually assigned addresses
      manual = all_floating.map{|addr| addr["ip"]}

      all_floating.sort{ |a,b|
        a_manual = manual.include? a
        b_manual = manual.include? b

        if a_manual and !b_manual
          -1
        elsif !a_manual and b_manual
          1
        else 0 end
      }
      all_floating.empty? ? manual : all_floating
    end

    def flavor_object
      return @flavor_object unless @flavor_object.nil?

      id = self.flavor["id"]
      return nil if id.blank?

      @service.flavor(id,true) rescue nil
    end

    def image_object
      return @image_object unless @image_object.nil?

      id = self.image["id"]
      return nil if id.blank?

      @service.image(id,true) rescue nil
    end

    def metadata
      attribute_to_object("metadata",Compute::Metadata)
    end

    def networks
      attribute_to_object("networks",Compute::Metadata)
    end

    def attached_volumes
      unless volumes_attached.empty?
        @service.volumes(id)
      else
        []
      end
    end

    ####################### ACTIONS #####################
    def add_fixed_ip(network_id)
      requires :id
      @service.add_fixed_ip(id,network_id)
    end

    def remove_fixed_ip(ip_address)
      requires :id
      @service.remove_fixed_ip(id,ip_address)
    end

    def terminate
      requires :id
      @service.delete_server id
    end

    def rebuild(image_ref, name, admin_pass=nil, metadata=nil, personality=nil)
      requires :id
      @service.rebuild_server(id, image_ref, name, admin_pass, metadata, personality)
      true
    end

    def resize(flavor_ref)
      requires :id
      @service.resize_server(id, flavor_ref)
      true
    end

    def create_image(name, metadata = {})
      requires :id
      @service.create_image(id,name, metadata)
      true
    end

    def revert_resize
      requires :id
      @service.revert_resize_server(id)
      true
    end

    def confirm_resize
      requires :id
      @service.confirm_resize_server(id)
      true
    end

    def reboot(type = 'SOFT')
      requires :id
      @service.reboot_server(id, type)
      true
    end

    def stop
      requires :id
      @service.stop_server(id)
    end

    def pause
      requires :id
      @service.pause_server(id)
    end

    def suspend
      requires :id
      @service.suspend_server(id)
    end

    def start
      requires :id

      case status.downcase
      when 'paused'
        @service.unpause_server(id)
      when 'suspended'
        @service.resume_server(id)
      else
        @service.start_server(id)
      end
    end

    def reset_vm_state(vm_state)
      requires :id
      @service.reset_server_state id, vm_state
    end

    def attach_volume(volume_id, device_name)
      requires :id
      @service.attach_volume(volume_id, id, device_name)
      true
    end

    def detach_volume(volume_id)
      requires :id
      @service.detach_volume(id, volume_id)
      true
    end

    def assign_security_group(sg_id)
      requires :id
      @service.add_security_group(id, sg_id)
      true
    end

    def unassign_security_group(sg_id)
      requires :id
      @service.remove_security_group(id, sg_id)
      true
    end

  end
end

