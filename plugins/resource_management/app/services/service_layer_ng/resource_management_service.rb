module ServiceLayerNg

  class ResourceManagementService < Core::ServiceLayerNg::Service

    include ProjectResource
    include DomainResource

  end
end
