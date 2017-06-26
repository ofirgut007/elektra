# this module is included in controllers.
# the controller should respond_to current_user (monsoon-openstack-auth gem)
module APIClient

  # load misty api client
  def api_client

    return nil unless current_user
    # initialize api_client unless already initialized
    puts "[api-client] -> api_client" if ENV['SERVICE_LAYER_DEBUG']
    return nil unless current_user.service_url('identity', {region: current_region, interface: 'public'})

    RequestStore.store[:user_api_client] ||= ::Misty::Cloud.new(
      auth:            misty_auth_params,
      region_id:       current_region,
      ssl_verify_mode: Rails.configuration.ssl_verify_peer
    )
  end

  def misty_auth_params
    
    #auth = ::Misty::AuthV3.new( context: { 
    #  catalog: current_user.context["catalog"],
    #  expires: current_user.context["expires_at"],
    #  token: current_user.token
    #})
    
    # https://github.com/sapcc/monsoon-openstack-auth#user-class-current_user
    return {
      context: { 
            catalog: current_user.context["catalog"],
            expires: current_user.context["expires_at"],
            token: current_user.token
      },
      domain_id:      current_user.domain_id,
      project_id:     current_user.project_id,
      user_domain_id: current_user.user_domain_id,
    }.reject { |_,value| value.nil? }
  end

end