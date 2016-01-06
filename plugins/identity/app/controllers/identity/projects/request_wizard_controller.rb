module Identity
  module Projects
    # This controller implemnts the workflow to create a project request
    class RequestWizardController < ::DashboardController
      def new
        @project = services.identity.new_project
        @project.enabled = true
      end

      def create
        @project = services.identity.new_project
        @project.attributes=params.fetch(:project, {}).merge(domain_id: @scoped_domain_id)

        inquiry = nil

        if @project.valid?
          inquiry = services.inquiry.inquiry_create(
              'project',
              @project.description,
              current_user,
              @project.attributes.to_json,
              Admin::IdentityService.list_scope_admins(domain_id: @scoped_domain_id, project_id: @scoped_project_id),
              {
                  "approved": {
                      "name": "Approve",
                      "action": "#{plugin('identity').domain_url(host: request.host_with_port, protocol: request.protocol)}?overlay=#{plugin('identity').projects_create_path}"
                  }
              }
          )
          unless inquiry.errors?
            render template: 'identity/projects/request_wizard/create.js'
          else
            render action: :new
          end
        else
          render action: :new
        end
      end
    end

    def edit
      @project = services.identity.new_project
      @project.attributes = @inquiry.payload
    end

    def update
      # user is not allowed to create a project (maybe)
      # so use admin identity for that!
      @project = services.identity.new_project
      @project.attributes = params.fetch(:project, {}).merge(domain_id: @scoped_domain_id)
      if @project.valid?
        inquiry = services.inquiry.inquiry_change(
            @inquiry.id,
            @project.description,
            @project.attributes.to_json
        )
        unless inquiry.errors?
          render template: 'identity/projects/request_wizard/create.js'
        else
          render action: :edit
        end
      else
        render action: :edit
      end
    end

    def load_and_authorize_inquiry
      @inquiry = services.inquiry.get_inquiry(params[:inquiry_id])

      if @inquiry
        unless current_user.is_allowed?("identity:create_wizard_create", {inquiry: {requester_uid: @inquiry.requester.uid}})
          render template: '/dashboard/not_authorized'
        end
      else
        render template: '/identity/projects/create_wizard/not_found'
      end
    end

  end
end