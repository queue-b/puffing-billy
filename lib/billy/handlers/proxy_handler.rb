require 'billy/handlers/handler'
require 'addressable/uri'
require 'eventmachine'
require 'em-synchrony/em-http'

module Billy
  class ProxyHandler
    include Handler

    def handles_request?(_method, url, _headers, _body)
      !disabled_request?(url)
    end

    def handle_request(method, url, headers, body)
      method = method.downcase
      return nil unless handles_request?(method, url, headers, body)

      opts = get_opts(url)

      req = EventMachine::HttpRequest.new(url, opts)
      # Dynamically call get/post/put, etc.
      req = req.send(method, build_request_options(url, headers, body))

      if req.error
        return { error: "Request to #{url} failed with error: #{req.error}" }
      end

      return nil unless req.response

      response = process_response(req)
      status = response[:status]

      unless allowed_response_code?(status)
        if Billy.config.non_successful_error_level == :error
          return { error: "[#{method.downcase}] #{url} #{status} for '#{url}' which was not allowed." }
        else
          Billy.log(:warn, "puffing-billy: Received response status code #{status} for '#{url}'")
        end
      end

      cache(url, headers, method, body, response) if cacheable?(url, status)

      Billy.log(:info, "puffing-billy: PROXY #{method} succeeded for '#{url}'")
      response
    end

    private

    def build_request_options(url, headers, body)
      headers = Hash[headers.map { |k, v| [k.downcase, v] }]
      headers.delete('accept-encoding')

      uri = Addressable::URI.parse(url)
      headers['authorization'] = [uri.user, uri.password] if uri.userinfo

      req_opts = {
        redirects: 0,
        keepalive: false,
        head: headers,
        ssl: { verify: false }
      }
      req_opts[:body] = body if body
      req_opts
    end

    def process_response(req)
      response = {
        status: req.response_header.status,
        headers: req.response_header.raw,
        content: req.response.force_encoding('BINARY')
      }

      response[:headers]['Connection'] = 'close'
      response
    end

    def disabled_request?(url)
      return false unless Billy.config.non_whitelisted_requests_disabled

      uri = Addressable::URI.parse(url)
      # In isolated environments, you may want to stop the request from happening
      # or else you get "getaddrinfo: Name or service not known" errors
      Billy.config.blacklisted_path?(uri.path) || !Billy.config.whitelisted_url?(uri)
    end

    def allowed_response_code?(status)
      successful_status?(status)
    end

    def get_opts(url)
      opts = {
        inactivity_timeout: Billy.config.proxied_request_inactivity_timeout,
        connect_timeout:    Billy.config.proxied_request_connect_timeout
      }

      if Billy.config.proxied_request_host && !bypass_internal_proxy?(url)
        opts[:proxy] = { host: Billy.config.proxied_request_host,
                         port: Billy.config.proxied_request_port }
      end

      opts
    end

    def cache(url, headers, method, body, response)
      scope = Billy::Cache.instance.scope
      key = Billy::Cache.instance.key(method.downcase, url, body)

      Billy::Cache.instance.store(
        key,
        scope,
        method.downcase,
        url,
        headers,
        body,
        response[:headers],
        response[:status],
        response[:content]
      )
    end

    def cacheable?(url, status)
      return false unless Billy.config.cache

      url = Addressable::URI.parse(url)
      # Cache the responses if they aren't whitelisted host[:port]s but always
      # cache blacklisted paths on any hosts
      cacheable_status?(status) &&
        (!Billy.config.whitelisted_url?(url) ||
          Billy.config.blacklisted_path?(url.path))
    end

    def successful_status?(status)
      (200..299).cover?(status) || status == 304
    end

    def cacheable_status?(status)
      Billy.config.non_successful_cache_disabled ? successful_status?(status) : true
    end

    def bypass_internal_proxy?(url)
      url.include?('localhost') ||
        url.include?('127.') ||
        url.include?('.dev') ||
        url.include?('.fin')
    end
  end
end
