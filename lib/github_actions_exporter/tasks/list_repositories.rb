# frozen_string_literal: true

module GitHubActionsExporter
  module Tasks
    class ListRepositories
      attr_reader :client, :logger

      def initialize(client, logger)
        @client = client
        @logger = logger
      end

      def work(options)
        logger.debug("Listing repositories")
        method, user_or_org = if options[:user]
          [:repositories, options[:user]]
        else
          [:organization_repositories, options[:organization]]
        end

        # TODO: Add backoff...
        repos = client.send(method, user_or_org, {per_page: 100})
        rels = client.last_response.rels

        while rels[:next] do
          repos.concat(client.get(rels[:next].href))
          rels = client.last_response.rels
        end

        repos
      end
    end
  end
end
