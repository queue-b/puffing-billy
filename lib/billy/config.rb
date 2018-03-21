require 'logger'
require 'tmpdir'

module Billy
  class Config
    DEFAULT_WHITELIST = ['127.0.0.1', 'localhost']
    RANDOM_AVAILABLE_PORT = 0 # https://github.com/eventmachine/eventmachine/wiki/FAQ#wiki-can-i-start-a-server-on-a-random-available-port

    attr_accessor :logger, :cache, :cache_request_headers, :whitelist, :path_blacklist, :ignore_params, :allow_params,
                  :persist_cache, :ignore_cache_port, :non_successful_cache_disabled, :non_successful_error_level,
                  :non_whitelisted_requests_disabled, :cache_path, :certs_path, :proxy_host, :proxy_port, :proxied_request_inactivity_timeout,
                  :proxied_request_connect_timeout, :dynamic_jsonp, :dynamic_jsonp_keys, :dynamic_jsonp_callback_name, :merge_cached_responses_whitelist,
                  :strip_query_params, :proxied_request_host, :proxied_request_port, :cache_request_body_methods, :after_cache_handles_request,
                  :cache_simulates_network_delays, :cache_simulates_network_delay_time, :record_stub_requests, :use_ignore_params

    def initialize
      @logger = defined?(Rails) ? Rails.logger : Logger.new(STDOUT)
      reset
    end

    def reset
      @cache = true
      @cache_request_headers = false
      @whitelist = DEFAULT_WHITELIST
      @path_blacklist = []
      @merge_cached_responses_whitelist = []
      @ignore_params = []
      @allow_params = []
      @persist_cache = false
      @dynamic_jsonp = false
      @dynamic_jsonp_keys = ['callback']
      @dynamic_jsonp_callback_name = 'callback'
      @ignore_cache_port = true
      @non_successful_cache_disabled = false
      @non_successful_error_level = :warn
      @non_whitelisted_requests_disabled = false
      @cache_path = File.join(Dir.tmpdir, 'puffing-billy')
      @certs_path = File.join(Dir.tmpdir, 'puffing-billy', 'certs')
      @proxy_host = 'localhost'
      @proxy_port = RANDOM_AVAILABLE_PORT
      @proxied_request_inactivity_timeout = 10 # defaults from https://github.com/igrigorik/em-http-request/wiki/Redirects-and-Timeouts
      @proxied_request_connect_timeout = 5
      @strip_query_params = true
      @proxied_request_host = nil
      @proxied_request_port = 80
      @cache_request_body_methods = ['post']
      @after_cache_handles_request = nil
      @cache_simulates_network_delays = false
      @cache_simulates_network_delay_time = 0.1
      @record_stub_requests = false
      @use_ignore_params = true
    end

    def whitelisted_url?(url)
      whitelist.any? do |value|
        if value.is_a?(Regexp)
          url.to_s =~ value || url.omit(:port).to_s =~ value
        else
          value =~ /^#{url.host}(?::#{url.port})?$/
        end
      end
    end

    def blacklisted_path?(path)
      !path_blacklist.index { |bl| bl.is_a?(Regexp) ? path =~ bl : path.include?(bl) }.nil?
    end
  end

  def self.configure
    yield config if block_given?
    config
  end

  def self.log(*args)
    config.logger.send(*args) unless config.logger.nil?
  end

  def self.config
    @config ||= Config.new
  end
end
