Raven.configure do |config|
  # httpclient is the only faraday adpater which handles no_proxy 
  config.http_adapter = :httpclient
  config.send_modules = false
  config.app_dirs_pattern = /(app|bin|config|lib|plugins|spec)/
  config.timeout = 3
end

module Excon
  module Sentry 
    class Middleware < Excon::Middleware::Base

      def response_call(datum)
        add_crumb(datum)
        @stack.response_call(datum)
      end

      def error_call(datum)
        add_crumb(datum)
        @stack.error_call(datum)
      end

      private

      def add_crumb(datum)
        Raven.breadcrumbs.record do |crumb|
          crumb.type = 'http'
          crumb.category = 'excon'
          data = {
            url: Excon::Utils.request_uri(datum),
            method: datum[:method].to_s.upcase
          }
          data[:status_code] = datum[:response][:status] if datum[:response]
          crumb.data = data
        end
      end

    end
  end
end

Excon.defaults[:middlewares].push Excon::Sentry::Middleware

