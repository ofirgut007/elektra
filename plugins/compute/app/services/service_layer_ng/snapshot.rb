module ServiceLayerNg
  # This module implements Openstack Domain API
  module Snapshot

    def image(image_id,use_cache = false)
      debug "[compute-service][Snapshot] -> image -> GET /images/#{image_id}"

      image_data = nil
      unless use_cache
        image_data = api.compute.show_image_details(image_id).data
        Rails.cache.write("server_image_#{image_id}", image_data, expires_in: 24.hours)
      else
        image_data = Rails.cache.fetch("server_image_#{image_id}", expires_in: 24.hours) do
          api.compute.show_image_details(image_id).data
        end
      end

      return nil if image_data.nil?
      map_to(Compute::Image image_data)
    end

    # this is called from server model
    def create_image(server_id, name, metadata={})
      # used for create snapshot
      debug "[compute-service][Snapshot] -> create_image #{name} -> POST /action"
      debug "[compute-service][Snapshot] -> create_image -> Metadata: #{metadata}"

      data = {
        'createImage' => {
            'name'     => name,
            'metadata' => metadata
        }
      }

      api.compute.create_image_createimage_action(server_id,data)
    end

  end
end