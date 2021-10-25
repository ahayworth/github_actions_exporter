# frozen_string_literal: true

require 'active_support'
require 'active_support/core_ext/numeric'
require 'active_support/duration'

module GitHubActionsExporter
  module Tasks
    class ListWorkflowRuns
      attr_reader :client, :logger

      def initialize(client, logger)
        @client = client
        @logger = logger
      end

      # TODO: Add backoff...
      def work(repo, status, created = nil)
        @logger.debug("[#{repo.full_name}] Fetching '#{status}' runs")
        # Fun fact: this means "please revalidate any non-expired
        # cache results you may have". Not "ignore cache" like you
        # might think. We use it to force a cache revalidation on
        # the first call to a paginated endpoint - and if the
        # first page hasn't changed, then we just allow the cache
        # to serve unexpired responses without forced revalidation.
        # This lets us get the freshest data possible without
        # running down our rate limit.
        headers = { "Cache-Control" => "no-cache" }
        args = { status: status, per_page: 100, headers: headers }
        args[:created] = ">=#{created.at_beginning_of_hour.iso8601}" unless created.nil?

        workflows = client.repository_workflow_runs(repo.full_name, args)[:workflow_runs]
        rels = client.last_response.rels

        trace = client.last_response.env[:http_cache_trace] || []
        # :valid indicates that a response was cached *and* that
        # the server told us it was good. We can stop forcing
        # revalidation now, we presume that the regular caching
        # logic will suffice - everything else should be valid, if
        # it's in the cache at all and not expired.
        # If it includes just about anything else, we want to force
        # the cache to double-check everything.
        if trace.include?(:valid)
          headers.delete("Cache-Control")
        end

        while rels[:next] do
          resp = client.get(rels[:next].href, { headers: headers })
          workflows.concat(resp[:workflow_runs])
          rels = client.last_response.rels
        end

        workflows
      end
    end
  end
end
