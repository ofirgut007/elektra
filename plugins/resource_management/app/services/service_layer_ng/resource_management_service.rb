module ServiceLayerNg

  class ResourceManagementService < Core::ServiceLayerNg::Service

    include ResourceManagementService::ProjectResource
    include ResourceManagementService::DomainResource
    include ResourceManagementService::CloudResource

    def quota_data(domain_id,project_id,options=[])
      debug "[resource management-service] -> quota_data"
      return [] if options.empty?

      project = find_project( 
        domain_id,
        project_id,
        services: options.collect { |values| values[:service_type] },
        resources: options.collect { |values| values[:resource_name] },
      )

      result = []
      options.each do |values|
        service = project.services.find { |srv| srv.type == values[:service_type].to_sym }
        next if service.nil?
        resource = service.resources.find { |res| res.name == values[:resource_name].to_sym }
        next if resource.nil?

        if values[:usage] and values[:usage].is_a?(Fixnum)
          resource.usage = values[:usage]
        end

        result << resource
      end
      
      result
    end

  end
end
