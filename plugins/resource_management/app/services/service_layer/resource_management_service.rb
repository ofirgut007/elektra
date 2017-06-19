module ServiceLayer

  class ResourceManagementService < Core::ServiceLayer::Service

    # https://github.com/sapcc/misty-limes/blob/master/lib/misty/openstack/limes/limes_v1.rb

    def available?(action_name_sym=nil)
      debug "[resource management-service] -> available?"
      not current_user.service_url('resources', region: region).nil?
    end

    def find_project(domain_id, project_id, options={})
      query = prepare_filter(options)
      debug "[resource management-service] -> find_project -> GET /v1/domains/#{domain_id}/projects/#{project_id}?#{query}"

      response = api_client.resources.get_project(domain_id, project_id, query)
      map_to(ResourceManagement::Project,response.body[project_id.nil? ? 'projects' : 'project'],domain_id: domain_id)
    end

    def list_projects(domain_id, options={})
      query = prepare_filter(options)
      debug "[resource management-service] -> list_projects -> GET /v1/domains/#{domain_id}?#{query}"

      response = api_client.resources.get_projects(domain_id, query)
      map_to(ResourceManagement::Project,response.body[project_id.nil? ? 'projects' : 'project'],domain_id: domain_id)
    end

    def find_domain(domain_id, options={})
      query = prepare_filter(options)
      debug "[resource management-service] -> find_domain -> GET /v1/domains/#{domain_id}?#{query}"

      response = api_client.resources.get_domain(domain_id,query)
      map_to(ResourceManagement::Domain,response.body[domain_id.nil? ? 'domains' : 'domain'])
    end

    def list_domains(options={})
      query = prepare_filter(options)
      debug "[resource management-service] -> list_domains -> GET /v1/domains/#{domain_id}?#{query}"

      response = api_client.resources.get_domains(query)
      map_to(ResourceManagement::Domain,response.body[domain_id.nil? ? 'domains' : 'domain'])
    end

    def find_current_cluster(options={})
      query = prepare_filter(options)
      debug "[resource management-service] -> find_current_cluster -> GET /v1/clusters/current?#{query}"

      response = api_client.resources.get_current_cluster(query)
      map_to(ResourceManagement::Cluster,response.body['cluster'])
    end

    def sync_project_asynchronously(domain_id, project_id)
      debug "[resource management-service] -> sync_project_asynchronously -> POST /v1/domains/#{domain_id}/projects/#{project_id}/sync"
      api_client.resources.sync_project(domain_id, project_id)
    end

    def has_project_quotas?
      debug "[resource management-service] -> has_project_quotas?"
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
      debug "[resource management-service] -> quota_data"
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
      debug "[resource management-service] -> update_new_style_resource"

      project_id        = update_attributes["project_id"] || nil
      project_domain_id = update_attributes["project_domain_id"] || nil
      domain_id         = update_attributes["domain_id"] || nil
      cluster_id        = update_attributes["cluster_id"] || nil

      services = [{
        type: update_attributes["service_type"],
        resources: [{
          name:     update_attributes["name"],
          quota:    update_attributes["quota"],
          capacity: update_attributes["capacity"],
          comment:  update_attributes["comment"],
        }.reject { |_,v| v.nil? }],
      }]

      debug "[resource management-service] -> update_new_style_resource -> resource: #{services}"

      if project_id && project_domain_id
        debug "[resource management-service] -> update_new_style_resource -> update project resource -> PUT /v1/domains/#{project_domain_id}/projects/#{project_id}"
        api_client.resources.set_quota_for_project(project_domain_id,project_id, :project => {:services => services})
      elsif domain_id
        debug "[resource management-service] -> update_new_style_resource -> update domain resource -> PUT /v1/domains/#{project_domain_id}"
        api_client.resources.set_quota_for_domain(domain_id, :domain => {:services => services})
      elsif cluster_id
        debug "[resource management-service] -> update_new_style_resource -> update cluster capacity -> PUT /v1/clusters/#{cluster_id}"
        api_client.resources.set_capacity_for_current_cluster(:cluster => {:services => services})
      else
        raise ArgumentError, "found nowhere to put quota: #{update_attributes.inspect}"
      end

      # need to return nil otherwise the resource object is after resource.save brocken
      return nil

    end

    private

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
