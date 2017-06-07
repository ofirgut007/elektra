require 'misty/openstack/limes'

# FIXME: check error handling for 404, 500 or 401

#module ResourceManagement
#  module Driver
#    class Misty < Interface
#      include Core::ServiceLayer::MistyDriver::ClientHelper
#
#      def initialize(params_or_driver)
#        super(params_or_driver)
#      end
#
#      def put_project_data(domain_id, project_id, services)
#        handle_response do
#          expect(Net::HTTPOK) do
#            misty.resources.set_quota_for_project(domain_id,project_id, :project => {:services => services})
#          end
#        end
#      end
#
#      def put_domain_data(domain_id, services)
#        handle_response do
#          expect(Net::HTTPOK) do
#            misty.resources.set_quota_for_domain(domain_id, :domain => {:services => services})
#          end
#        end
#      end
#
#      def put_cluster_data(services)
#        handle_response do
#          expect(Net::HTTPOK) do
#            misty.resources.set_capacity_for_current_cluster(:cluster => {:services => services})
#          end
#        end
#      end
#
#      ##########################################################################
#      # error handling
#      #
#      # Misty does not do any error handling by itself. It returns a
#      # Net::HTTPResponse instance, or rather, an instance of a subclass of
#      # Net::HTTPResponse. The concrete subclass indicates the HTTP status code
#      # in the response, e.g. 401 responses will be instances of
#      # Net::HTTPUnauthorized.
#      #
#      # expect() wraps responses with unexpected status codes into a custom
#      # exception class (see below) and raises the exception, so that Elektra's
#      # regular error handling can commence.
#
#      def expect(*classes)
#        response = yield
#        raise BackendError.new(response) unless classes.include?(response.class)
#        return response
#      end
#
#      class BackendError < ::StandardError
#        attr_reader :response
#
#        def initialize(response)
#          @response = response
#
#          # make @response behave more like an Excon error
#          def @response.get_header(key)
#            get_fields(key).first
#          end
#        end
#
#        def error_name
#          # mimics Fog-like status-specific error class names (one per status code)
#          # e.g. "Not Found" -> "NotFound"
#          @response.message.gsub(' ', '')
#        end
#
#        def to_str
#          @response.body.to_s
#        end
#      end
#
#    end
#  end
#end
