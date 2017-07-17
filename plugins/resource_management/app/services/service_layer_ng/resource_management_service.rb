module ServiceLayerNg

  class ResourceManagementService < Core::ServiceLayerNg::Service

    include ProjectResource
    include DomainResource

    # placeholder, will be removed later
    def debug(message) 
      puts message
    end

  end
end
