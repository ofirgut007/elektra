module ServiceLayerNg
  # This module implements Openstack Group API
  module ResourceManagementService::CloudResource

    def find_current_cluster(query={})
      debug "[resource management-service][CloudResource] -> find_current_cluster -> GET /v1/clusters/current"
      debug "[resource management-service][CloudResource] -> find_current_cluster -> Query: #{query}"

      api.resources.get_current_cluster(query).map_to(ResourceManagement::Cluster)
    end
    
    
  end
end