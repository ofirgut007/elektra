module ServiceLayer

  class ResourceManagementService < Core::ServiceLayer::Service

    def available?(action_name_sym=nil)
      not current_user.service_url('resources', region: region).nil?
    end

    def find_project(domain_id, project_id, options={})
      puts "find_project"
      query = prepare_filter(options)
      response = api_client.resources.get_project(domain_id, project_id, query)
      map_to(ResourceManagement::Project,response.body[project_id.nil? ? 'projects' : 'project'],domain_id: domain_id)
    end

    def list_projects(domain_id, options={})
      puts "list_projects"
      query = prepare_filter(options)
      response = api_client.resources.get_projects(domain_id, query)
      map_to(ResourceManagement::Project,response.body[project_id.nil? ? 'projects' : 'project'],domain_id: domain_id)
    end

    def find_domain(domain_id, options={})
      puts "find_domain"
      query = prepare_filter(options)
      response = api_client.resources.get_domain(domain_id,query)
      map_to(ResourceManagement::Domain,response.body[domain_id.nil? ? 'domains' : 'domain'])
    end

    def list_domains(options={})
      puts "list_domains"
      query = prepare_filter(options)
      response = api_client.resources.get_domains(query)
      map_to(ResourceManagement::Domain,response.body[domain_id.nil? ? 'domains' : 'domain'])
    end

    def find_current_cluster(options={})
      puts "find_current_cluster"
      query = prepare_filter(options)
      response = api_client.resources.get_current_cluster(query)
      map_to(ResourceManagement::Cluster,response.body['cluster'])
    end

    def sync_project_asynchronously(domain_id, project_id)
      api_client.resources.sync_project(domain_id, project_id)
    end

    def has_project_quotas?
      project = find_project(
        current_user.domain_id || current_user.project_domain_id,
        current_user.project_id,
        services:  [ 'compute',                   'network',  'object-store' ],
        resources: [ 'instances', 'ram', 'cores', 'networks', 'capacity'     ],
      )
      # return true if approved_quota of the resource networking:networks is greater than 0
      # OR
      # return true if the sum of approved_quota of the resources compute:instances,
      # compute:ram, compute:cores and object_storage:capacity is greater than 0
      return project.resources.any? { |r| r.quota > 0 }
    end

    def quota_data(options=[])
      return [] if options.empty?

      project = find_project(
        current_user.domain_id || current_user.project_domain_id,
        current_user.project_id,
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

      return result
      # even if my user has the role resource_viewer the API throws the Unauthorized exception!
    rescue Core::ServiceLayer::Errors::ApiError => e
      []
    end

    def update_new_style_resource(id,update_attributes)

      #TODO: for some reason after resource.save the resource object is brocken?

      project_id        = update_attributes["project_id"] || nil
      project_domain_id = update_attributes["project_domain_id"] || nil
      domain_id         = update_attributes["domain_id"] || nil
      cluster_id        = update_attributes["cluster_id"] || nil

      puts "update_new_style_resource"
      pp update_attributes

      services = [{
        type: update_attributes["service_type"],
        resources: [{
          name:     update_attributes["name"],
          quota:    update_attributes["quota"],
          capacity: update_attributes["capacity"],
          comment:  update_attributes["comment"],
        }.reject { |_,v| v.nil? }],
      }]

      if project_id && project_domain_id
        puts "update project resource"
        api_client.resources.set_quota_for_project(project_domain_id,project_id, :project => {:services => services})
      elsif domain_id
        puts "update domain resource"
        api_client.resources.set_quota_for_domain(domain_id, :domain => {:services => services})
      elsif cluster_id
        puts "update cluster capacity"
        api_client.resources.set_capacity_for_current_cluster(:cluster => {:services => services})
      else
        raise ArgumentError, "found nowhere to put quota: #{update_attributes.inspect}"
      end

    end

    # this is for misty
    def prepare_filter(options)
      query = {
        service:  options[:services],
        resource: options[:resources],
      }.reject { |_,v| v.nil? }
      return Excon::Utils.query_string(query: query).sub(/^\?/, '')
    end

  end
end
