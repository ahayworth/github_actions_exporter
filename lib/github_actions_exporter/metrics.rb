# frozen_string_literal: true

require 'thread'
require 'prometheus/client'
require 'prometheus/client/formats/text'

module GitHubActionsExporter
  class Metrics
    attr_reader \
      :incomplete_workflow_runs,
      :workflow_run_duration,
      :rate_limit_remaining

    def initialize(logger, registry = Prometheus::Client.registry)
      @logger = logger
      @mutex = Mutex.new
      @in_progress = {}

      @registry = registry
      create_metrics!
    end

    def to_s
      Prometheus::Client::Formats::Text.marshal(@registry)
    end

    def oldest_run_for(repo_name)
      @mutex.synchronize do
        @in_progress[repo_name] ||= {}
        @in_progress[repo_name].min_by do |_, run|
          # TODO is this right?
          run.run_started_at || run.created_at
        end
      end
    end

    # Tracks count of on-going jobs by repo, job name, and status.
    # Also, tracks duration of completed jobs if we've previously
    # tracked it as on-going.
    #
    # This means we will necessarily miss jobs that start _and_
    # finish between refresh intervals. For example, given a
    # refresh interval of 5 seconds and the following timeline:
    #   - t0: refresh
    #   - t1: job start
    #   - t4: job finish
    #   - t5: refresh
    # Then we will never have stats for that job - it will never
    # show up in counts (almost certainly fine), and we'll never
    # track its duration (not quite as fine). One way to mitigate
    # this might be to just ask github for *all* statuses and
    # remember the furthest-back job we saw last time, and just
    # iterate through all jobs since then. However, if you have
    # an older job which takes longer than a newer job, then you
    # must remember to skip over the completed "newer" job each
    # time you paginate through (and such calls are slower, anyways).
    #
    # If you're reading this comment and you're missing jobs, you
    # can always lower the refresh interval and your prometheus
    # scrape interval. Beware of API rate-limits, however - we try
    # hard not to needlessly waste request, but on a busy repo
    # with a low refresh interval, there's only so much we can do.
    #
    # Callers are responsible for looking through all possible
    # statuses from the GitHub API. If a job transitions through
    # an untracked status, then for the duration of that un-tracked
    # status the counters will reflect only the last tracked status.
    # For example, if a job transitions through states:
    #   {t0, s0} -> {t1, s1} -> {t2, s2}
    # but callers are only looking for states s0 and s2, then we will
    # have the following counts at certain times:
    #   - t0: {s0: 1}
    #   - t1: {s0: 1},
    #   - t2: {s0: 0, s2: 1}
    # Basically, we just "miss" the intermediate step. This is
    # probably fine though.
    def observe_job(new_job)
      old_job = nil
      repo_name = new_job.repository.full_name

      debug_details = {
        id:     new_job.id,
        name:   new_job.name,
        status: new_job.status,
        repo:   new_job.repository.full_name,
      }
      @logger.debug("Observing job: #{debug_details.inspect}")

      @mutex.synchronize do
        @in_progress[repo_name] ||= {}
        old_job = @in_progress[repo_name].delete(new_job.id)
      end

      if old_job
        @incomplete_workflow_runs.decrement(labels: {
          name:       new_job.name,
          status:     old_job.status,
          repository: repo_name,
        })

        # We only want to track durations for jobs that were
        # enqueued since we started. Otherwise, we have to pick
        # a starting point and rewind - and that's a lot more
        # complicated to implement.
        if new_job.status == "completed"
          elapsed = new_job.updated_at - new_job.run_started_at
          @workflow_run_duration.observe(elapsed, labels: {
            name:       new_job.name,
            repository: repo_name,
          })
        end
      end

      # For any other kind of job status, we want to track.
      unless new_job.status == "completed"
        @mutex.synchronize do
          @in_progress[repo_name][new_job.id] = new_job
        end

        @incomplete_workflow_runs.increment(labels: {
          name:       new_job.name,
          status:     new_job.status,
          repository: repo_name,
        })
      end
    end

    def observe_rate_limit(rl)
      @rate_limit_remaining.set(rl.remaining)
    end

    private
    def create_metrics!
      @incomplete_workflow_runs = @registry.gauge(
        :github_actions_incomplete_workflow_runs,
        docstring: 'Current count of incomplete workflow runs',
        labels: [
          :repository,
          :status,
          :name,
        ],
      )

      # TODO: Make the histogram buckets a CLI option
      buckets = Prometheus::Client::Histogram.exponential_buckets(
        start: 15, factor: 2, count: 7
      )
      # We want  to track two additional buckets that don't fit
      # the exponential curve.
      buckets = [5.0, 10.0] + buckets

      @workflow_run_duration = @registry.histogram(
        :github_actions_workflow_run_duration_seconds,
        docstring: 'Workflow run duration for completed jobs, in seconds',
        labels: [
          :repository,
          :name,
        ],
        buckets: buckets,
      )

      @rate_limit_remaining = @registry.gauge(
        :github_actions_exporter_rate_limit_remaining,
        docstring: 'Remaining calls left for the GitHub v3 REST API',
      )

    end
  end
end
