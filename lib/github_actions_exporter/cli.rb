# frozen_string_literal: true

require 'active_support'
require 'optparse'

require_relative './client'
require_relative './metrics'
require_relative './tasks'

module GitHubActionsExporter
  class CLI
    # TODO: Support GHE urls
    # TODO: Support OAuth Apps
    def initialize
      @options = {
        "log-level":        env_or_default("LOG_LEVEL", "info"),
        user:               env_or_default("USER", nil),
        organization:       env_or_default("ORGANIZATION", nil),
        repos:              env_or_default("REPOS", nil),
        interval:           env_or_default("INTERVAL", 30),
        token:              env_or_default("TOKEN", nil),
        "pem-file":         env_or_default("PEM_FILE", nil),
        "installation-id":  env_or_default("INSTALLATION_ID", nil),
        "app-id":           env_or_default("APP_ID", nil),
      }

      parse_options!
    end

    def run
      # TODO make logger global
      logger = Logger.new(STDOUT)
      logger.level = @options[:"log-level"]

      metrics = GitHubActionsExporter::Metrics.new(logger)

      # TODO: cache size limit option
      cache = ActiveSupport::Cache::MemoryStore.new
      gh = GitHubActionsExporter::Client.new(@options, logger, cache)
      gh.access_token = gh.regenerate_installation_access_token if @options[:"pem-file"]

      statuses = ["queued", "in_progress", "waiting", "requested"].freeze

      # TODO: make this a worker model rather than independent threads
      repos = GitHubActionsExporter::Tasks::ListRepositories.new(gh, logger).work(@options)
      threads = []

      repo_workers = repos.each_with_object({}) do |repo, h|
        local_gh = GitHubActionsExporter::Client.new(@options, logger, cache)
        local_gh.access_token = local_gh.regenerate_installation_access_token if @options[:"pem-file"]
        h[repo.full_name] = GitHubActionsExporter::Tasks::ListWorkflowRuns.new(local_gh, logger)
      end

      repos.each do |repo|
        threads << Thread.new do
          loop do
            logger.info "[#{repo.full_name}] Synchronizing with the GitHub API"
            statuses.each do |status|
              begin
                runs = repo_workers[repo.full_name].work(repo, status)
              rescue => e
                logger.error("Exception processing #{repo.full_name} - #{status}: #{e}")
                next
              end

              grouped_runs = runs.group_by(&:name)
              grouped_runs.each do |name, runs|
                runs.each do |run|
                  metrics.observe_job(run)
                end
              end
            end

            _, oldest_run = metrics.oldest_run_for(repo.full_name)
            if oldest_run
              begin
                logger.debug "[#{repo.full_name}] Fetching completed runs"
                # TODO run_started_at || created_at - is that right?
                completed_runs = repo_workers[repo.full_name].work(repo, "completed", (oldest_run.run_started_at || oldest_run.created_at))
                completed_runs.each do |run|
                  metrics.observe_job(run)
                end
              rescue => e
                logger.error("Exception processing #{repo.full_name} - #{status}: #{e}")
                next
              end
            end

            sleep @options[:interval]
          end
        end
      end

      threads << Thread.new do
        loop do
          rl = gh.rate_limit!
          metrics.observe_rate_limit(rl)

          logger.debug(metrics.to_s)
          logger.debug(rl)

          logger.debug("Sleeping #{@options[:interval]}")
          sleep @options[:interval]
        end
      end

      threads.each(&:join)
    end

    private
    def env_or_default(key, default)
      env_key = "GITHUB_ACTIONS_EXPORTER_#{key}"
      ENV[env_key].to_s != "" ? ENV[env_key].to_s : default
    end

    def parse_options!
      cli_opts = {}

      opts = OptionParser.new do |opts|
        opts.banner = <<~EOF
          Usage: github_actions_exporter --organization ORG --repos LIST,OF,REPOS

          All options may be specified as a CLI switch, or an environment variable with the prefix 'GITHUB_ACTIONS_EXPORTER_'
          For example, '--user foo' may instead be specified in the environment as 'GITHUB_ACTIONS_EXPORTER_USER=foo'.
          CLI switches take priority over environment variables.

        EOF

        user_org_exclusive = "--user or --organization must be provided, but not both."
        token_pem_exclusive = "--token or --pem-file must be provided, but not both."
        # TODO - validate options for log level
        opts.on("--log-level LEVEL", String, "Default: info")
        opts.on("--user USER", String, "GitHub user to scan. #{user_org_exclusive}")
        opts.on("--organization ORGANIZATION", String, "GitHub organization to scan. #{user_org_exclusive}")
        opts.on("--repos REPOS", Array, "Comma-separated list of repositories. If none is provided, all will be scanned")
        opts.on("--interval INTERVAL", Integer, "Seconds to sleep between scans")
        opts.on("--token TOKEN", String, "GitHub token for authentication. #{token_pem_exclusive}")
        opts.on("--pem-file FILE", String, "Github App PEM file for authentication. #{token_pem_exclusive}")
        opts.on("--installation-id ID", String, "GitHub App installation ID for authentication.")
        opts.on("--app-id ID", String, "GitHub App ID for authentication.")
      end
      opts.parse!(into: cli_opts)

      @options = @options.merge(cli_opts)

      if !@options[:organization] && !@options[:user]
        abort "Missing required flag: --user or --organization\n\n#{opts.help}"
      end

      if @options[:organization] && @options[:user]
        abort "--user and --organization are mutually exclusive\n\n#{opts.help}"
      end

      if @options[:interval] <= 0
        abort "--interval must be a positive number\n\n#{opts.help}"
      end

      if @options[:token] && @options[:"pem-file"]
        abort "--token and --pem-file are mutually exclusive\n\n#{opts.help}"
      end

      if !@options[:token] && !@options[:"pem-file"]
        abort "Either --token or --pem-file are required.\n\n#{opts.help}"
      end

      if @options[:"--pem-file"] && (@options[:"--installation-id"].nil? || @options[:"--app-id"].nil?)
        abort "Must pass --installation-id and --app-id when using --pem-file\n\n#{opts.help}"
      end
    end
  end
end
