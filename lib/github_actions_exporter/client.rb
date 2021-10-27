# frozen_string_literal: true

require 'delegate'
require 'logger'

require 'faraday-http-cache'
# require 'httpx/adapters/faraday'
require 'openssl'
require 'jwt'
require 'octokit'

module GitHubActionsExporter
  class Client < DelegateClass(Octokit::Client)
    attr_reader :cli_options

    def initialize(cli_options, logger, cache_store)
      @cli_options = cli_options
      @logger = logger

      new_middleware = Octokit::Default.middleware.dup

      # TODO: make this an option
      # TODO: Add an instrumenter (ActiveSupport Instrumentation, I think)
      # ref: https://lostisland.github.io/faraday/middleware/logger
      # new_middleware.response(:logger, logger, { headers: true, bodies: false })
      new_middleware.response(:logger, @logger, { headers: false, bodies: false, log_level: :debug })

      # TODO: make this an option
      # TODO: Add an instrumenter (ActiveSupport Instrumentation, I think)
      # TODO: Should the caching privacy (shared_cache) be configurable?
      # ref: https://github.com/sourcelevel/faraday-http-cache
      new_middleware.use(
        :http_cache,
        store: cache_store,
        serializer: Marshal,
        logger: @logger,
        shared_cache: false
      )

      # new_middleware.adapter :httpx

      Octokit.configure do |c|
        c.middleware = new_middleware

        # TODO: make these options
        c.connection_options = {
          request: {
            open_timeout: 2,
            timeout: 5,
          }
        }

        # TODO: pemfile auth
        # TODO: OAuth
        if cli_options[:token]
          c.access_token = cli_options[:token]
        end
      end

      super(Octokit::Client.new)
    end

    def regenerate_installation_access_token
      temp_client = Octokit::Client.new
      temp_client.bearer_token = generate_jwt
      access_token = temp_client.create_app_installation_access_token(cli_options[:"installation-id"])
      access_token[:token]
    end

    private
    def generate_jwt
      private_key = OpenSSL::PKey::RSA.new(File.read(cli_options[:"pem-file"]))
      payload = {
        iat: Time.now.to_i - 60,
        exp: Time.now.to_i + (10 * 60),
        iss: cli_options[:"app-id"],
      }

      JWT.encode(payload, private_key, "RS256")
    end
  end
end
