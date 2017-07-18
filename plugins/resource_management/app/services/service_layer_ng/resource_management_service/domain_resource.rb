module ServiceLayerNg
  # This module implements Openstack Group API
  module ResourceManagementService::DomainResource

    def find_domain(domain_id, query={})
      debug "[resource management-service][DomainResource] -> find_domain -> GET /v1/domains/#{domain_id}"
      debug "[resource management-service][DomainResource] -> find_domain -> Query: #{query}"

      api.resources.get_domain(domain_id,query).map_to(ResourceManagement::Domain)
    end

    def list_domains(query={})
      debug "[resource management-service][DomainResource] -> list_domains -> GET /v1/domains/#{query}"
      debug "[resource management-service][DomainResource] -> list_domains -> Query: #{query}"

      api.resources.get_domains(query).map_to(ResourceManagement::Domain)
    end
    
  end
end