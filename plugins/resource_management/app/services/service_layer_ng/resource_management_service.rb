module ServiceLayerNg

  class ResourceManagementService < Core::ServiceLayerNg::Service

    include ProjectResource

    # placeholder, will be removed later
    def debug(message) 
      puts message
    end

  end
end
