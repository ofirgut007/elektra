module ServiceLayerNg

  class ResourceManagementService < Core::ServiceLayerNg::Service

    include ResourceManagementService::ProjectResource
    include ResourceManagementService::DomainResource

  end
end
