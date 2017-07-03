module Compute
  # Compute calls
  module Driver
    class Fog < Interface
      include Core::ServiceLayer::FogDriver::ClientHelper

      def initialize(params)
        super(params)
        @fog = ::Fog::Compute::OpenStack.new(auth_params)
      end

      def create_server(params={})
        name = params.delete("name")
        image_ref = params.delete("imageRef")
        flavor_ref = params.delete("flavorRef")
        params["max_count"]=params["max_count"].to_i if params["max_count"]
        params["min_count"]=params["min_count"].to_i if params["min_count"]
        if networks=params.delete("networks")
          params["nics"]=networks.collect { |n| {'net_id' => n["id"], 'v4_fixed_ip' => n['fixed_ip'], 'port_id' => n['port']} }
        end

        handle_response { @fog.create_server(name, image_ref, flavor_ref, params).body['server'] }
      end

      def delete_server(server_id)
        handle_response { @fog.delete_server(server_id) }
      end

      def reboot_server(server_id, type)
        handle_response { @fog.reboot_server(server_id, type) }
      end

      def rebuild_server(server_id, image_ref, name, admin_pass=nil, metadata=nil, personality=nil)
        handle_response { @fog.rebuild_server(server_id, image_ref, name, admin_pass, metadata, personality) }
      end

      def resize_server(server_id, flavor_ref)
        handle_response { @fog.resize_server(server_id, flavor_ref) }
      end

      def confirm_resize_server(server_id)
        handle_response { @fog.confirm_resize_server(server_id) }
      end

      def revert_resize_server(server_id)
        handle_response { @fog.revert_resize_server(server_id) }
      end

      def create_image(server_id, name, metadata={})
        handle_response { @fog.create_image(server_id, name, metadata).body['image'] }
      end

      def start_server(server_id)
        handle_response { @fog.start_server(server_id) }
      end

      def stop_server(server_id)
        handle_response { @fog.stop_server(server_id) }
      end

      def attach_volume(volume_id, server_id, device)
        handle_response { @fog.attach_volume(volume_id, server_id, device) }
      end

      def detach_volume(server_id, volume_id)
        handle_response { @fog.detach_volume(server_id, volume_id) }
      end

      def suspend_server(server_id)
        handle_response { @fog.suspend_server(server_id) }
      end

      def pause_server(server_id)
        handle_response { @fog.pause_server(server_id) }
      end

      def unpause_server(server_id)
        handle_response { @fog.unpause_server(server_id) }
      end

      def reset_server_state(server_id, state)
        handle_response { @fog.reset_server_state(server_id, state) }
      end

      def rescue_server(server_id)
        handle_response { @fog.rescue_server(server_id) }
      end

      def resume_server(server_id)
        handle_response { @fog.resume_server(server_id) }
      end

      def add_fixed_ip(server_id, network_id)
        handle_response{@fog.add_fixed_ip(server_id, network_id)}
      end

      def remove_fixed_ip(server_id, address)
        handle_response{@fog.remove_fixed_ip(server_id, address)}
      end

      def usage(filter = {})
        handle_response { @fog.get_limits(filter).body['limits']['absolute'] }
      end

      ############################# HYPERVISORS ##############################

      def hypervisors(filter = {})
        handle_response { @fog.list_hypervisors_detail(filter).body['hypervisors'] }
      end

      def get_hypervisor(id)
        handle_response { @fog.get_hypervisor(id).body['hypervisor'] }
      end

      def hypervisor_servers(name)
        # FIXME: asking nova with hv name works instead of id? maybe higher microversion will do
        handle_response { @fog.list_hypervisor_servers(name).body['hypervisors'].first['servers'] }
      end

      ############################# SERVICES ##############################

      def services(filter = {})
        handle_response { @fog.list_services(filter).body['services'] }
      end

      def disable_service_reason(host, name, reason, options = {})
        handle_response { @fog.disable_service_log_reason(host, name, reason, options) }
      end

      def disable_service(host, name, options = {})
        handle_response { @fog.disable_service(host, name, options) }
      end

      def enable_service(host, name, options = {})
        handle_response { @fog.enable_service(host, name, options) }
      end

      ##################### HOST AGGREGATES #########################

      def host_aggregates(filter = {})
        handle_response { @fog.list_aggregates(filter).body['aggregates'] }
      end

      ############################# OS INTERFACES ##############################
      def create_os_interface(server_id,options={})
        handle_response{@fog.create_os_interface(server_id,options).body['interfaceAttachment']}
      end

      def delete_os_interface(server_id,port_id)
        handle_response{@fog.delete_os_interface(server_id,port_id)}
      end

      def list_os_interfaces(server_id)
        handle_response{@fog.list_os_interfaces(server_id).body['interfaceAttachments']}
      end

      ########################### FLAVORS #############################
      def flavors(filter={})
        handle_response { @fog.list_flavors_detail(filter).body['flavors'] }
      end

      def get_flavor(flavor_id)
        handle_response { @fog.get_flavor_details(flavor_id).body['flavor'] }
      end

      def delete_flavor(id)
        handle_response {
          @fog.delete_flavor(id)
          true
        }
      end

      def create_flavor(attributes)
        handle_response { @fog.create_flavor(attributes).body['flavor']}
      end

      def add_flavor_access_to_tenant(flavor_id,tenant_id)
        handle_response {@fog.add_flavor_access(flavor_id, tenant_id).body['flavor_access']}
      end

      def remove_flavor_access_from_tenant(flavor_id,tenant_id)
        handle_response{@fog.remove_flavor_access(flavor_id, tenant_id).body['flavor_access']}
      end

      def list_flavor_members(flavor_id)
        handle_response{@fog.list_tenants_with_flavor_access(flavor_id).body['flavor_access']}
      end

      def create_flavor_metadata(flavor_id,specs_data)
        handle_response{@fog.create_flavor_metadata(flavor_id, specs_data).body['extra_specs']}
      end

      def delete_flavor_matadata(flavor_id,key)
        handle_response{ @fog.delete_flavor_metadata(flavor_id, key)}
      end

      def get_flavor_metadata(flavor_id)
        handle_response{@fog.get_flavor_metadata(flavor_id).body['extra_specs']}
      end

      ########################### IMAGES #############################
      def images(filter={})
        handle_response { @fog.list_images(filter).body['images'] }
      end

      def get_image(image_id)
        handle_response { @fog.get_image_details(image_id).body['image'] }
      end

      def delete_image(id)
        handle_response {
          @fog.delete_image(id)
          true
        }
      end

      ########################### AVAILABILITY_ZONES #############################

      def availability_zones(filter={})
        handle_response { @fog.list_availability_zones(filter).body['availabilityZoneInfo'] }
      end

      ########################### SECURITY_GROUPS #############################
      def create_security_group(params={})
        handle_response { @fog.security_groups.create(params) }
      end

      def security_groups(filter={})
        handle_response { @fog.list_security_groups.body['security_groups'] }
      end

      def server_security_groups(server_id)
        handle_response { @fog.list_security_groups(server_id: server_id).body['security_groups'] }
      end

      def get_security_group(id)
        handle_response { @fog.get_security_group(id).body['security_group'] }
      end

      def delete_security_group(id)
        handle_response {
          @fog.delete_security_group(id)
          true
        }
      end

      def add_security_group(id, sg_id)
        handle_response { @fog.add_security_group(id, sg_id) }
      end

      def remove_security_group(id, sg_id)
        handle_response { @fog.remove_security_group(id, sg_id) }
      end

      ########################### VOLUMES #############################
      def create_volume(params={})
        handle_response { @fog.create_volume(name, description, size, options).body['volume'] }
      end

      def volumes(filter={})
        handle_response { @fog.list_volumes_detail(filter).body['volumes'] }
      end

      def get_volume(id)
        handle_response { @fog.get_volume_details(id).body['volume'] }
      end

      def delete_volume(id)
        handle_response {
          @fog.delete_volume(id)
          true
        }
      end

      ##################### KEYPAIRS #########################
      def keypairs(filter={})
        handle_response { @fog.list_key_pairs(filter).body['keypairs'] }
      end

      def get_keypair(name)
        handle_response { @fog.get_key_pair(name).body['keypair'] }
      end

      def create_keypair(params = {})
        handle_response { @fog.create_key_pair(params['name'], params['public_key']).body['keypair'] }
      end

      def delete_keypair(name)
        handle_response {
          @fog.delete_key_pair(name)
        }
      end

    end
  end
end
