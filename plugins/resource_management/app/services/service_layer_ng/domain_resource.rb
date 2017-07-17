module ServiceLayerNg
  # This module implements Openstack Group API
  module DomainResource

    def find_domain(domain_id, options={})
      debug "[resource management-service][DomainResource] -> find_domain -> GET /v1/domains/#{domain_id}"
      debug "[resource management-service][DomainResource] -> find_domain -> Options: #{options}"

      response = api_client.resources.get_domain(domain_id,query)
      map_to(ResourceManagement::Domain,response.body[domain_id.nil? ? 'domains' : 'domain'])
    end

    def list_domains(options={})
      debug "[resource management-service][DomainResource] -> list_domains -> GET /v1/domains/#{domain_id}"
      debug "[resource management-service][DomainResource] -> list_domains -> Options: #{options}"

      api.resources.get_domains(query).map_to(ResourceManagement::Domain)
    end
    
  end
end