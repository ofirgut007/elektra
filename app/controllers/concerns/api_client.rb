# this module is included in controllers.
# the controller should respond_to current_user (monsoon-openstack-auth gem)
module APIClient

  # load misty api client
  def api_client
    return nil unless current_user
    # initialize api_client unless already initialized
    puts "[api-client] -> api_client" if ENV['SERVICE_LAYER_DEBUG']
    return nil unless current_user.service_url('identity', {region: current_region, interface: 'public'})

    @misty_cloud ||= ::Misty::Cloud.new(
      auth:            misty_auth_params,
      region_id:       current_region,
      ssl_verify_mode: Rails.configuration.ssl_verify_peer,
      http_proxy:      ENV['http_proxy'],
    )
  end

  def misty_auth_params
    # https://github.com/sapcc/monsoon-openstack-auth#user-class-current_user
    return {
      url:            current_user.service_url('identity', {region: current_region, interface: 'public'}),
      token:          current_user.token,
      domain_id:      current_user.domain_id,
      project_id:     current_user.project_id,
      user_domain_id: current_user.user_domain_id,
    }.reject { |_,value| value.nil? }
  end

end