## Workflow Runs

#### github_actions_incomplete_workflow_runs

```
# TYPE github_actions_incomplete_workflow_runs gauge
# HELP github_actions_incomplete_workflow_runs Current count of incomplete workflow runs
```

Counts incomplete workflow runs. Typical example:

```
github_actions_incomplete_workflow_runs{name="workflow_name",status="queued",repository="some-org-or-user/some-repo"} 0.0
github_actions_incomplete_workflow_runs{name="workflow_name",status="in_progress",repository="some-org-or-user/some-repo"} 0.0
```

Completed runs are not explicitly tracked in this metric, because we do not parse all job history at startup.

#### github_actions_workflow_run_duration_seconds

```
# TYPE github_actions_workflow_run_duration_seconds histogram
# HELP github_actions_workflow_run_duration_seconds Workflow run duration for completed jobs, in seconds
```

Tracks the duration of different kinds of GitHub Actions workflow runs. The duration is calculated when we detect that a job has finished, and it calculates the delta between `updated_at` and `run_started_at` in the Actions API for that run.

Default histogram buckets: `[5.0, 10.0, 15.0, 30.0, 60.0, 120.0, 240.0, 480.0, 960.0]`

Typical example:

```
github_actions_workflow_run_duration_seconds_bucket{name="workflow_name",repository="some-org-or-user/some-repo",le="5.0"} 0.0
github_actions_workflow_run_duration_seconds_bucket{name="workflow_name",repository="some-org-or-user/some-repo",le="10.0"} 0.0
github_actions_workflow_run_duration_seconds_bucket{name="workflow_name",repository="some-org-or-user/some-repo",le="15.0"} 0.0
github_actions_workflow_run_duration_seconds_bucket{name="workflow_name",repository="some-org-or-user/some-repo",le="30.0"} 1.0
github_actions_workflow_run_duration_seconds_bucket{name="workflow_name",repository="some-org-or-user/some-repo",le="60.0"} 1.0
github_actions_workflow_run_duration_seconds_bucket{name="workflow_name",repository="some-org-or-user/some-repo",le="120.0"} 1.0
github_actions_workflow_run_duration_seconds_bucket{name="workflow_name",repository="some-org-or-user/some-repo",le="240.0"} 1.0
github_actions_workflow_run_duration_seconds_bucket{name="workflow_name",repository="some-org-or-user/some-repo",le="480.0"} 1.0
github_actions_workflow_run_duration_seconds_bucket{name="workflow_name",repository="some-org-or-user/some-repo",le="960.0"} 1.0
github_actions_workflow_run_duration_seconds_bucket{name="workflow_name",repository="some-org-or-user/some-repo",le="+Inf"} 1.0
github_actions_workflow_run_duration_seconds_sum{name="workflow_name",repository="some-org-or-user/some-repo"} 28.0
github_actions_workflow_run_duration_seconds_count{name="workflow_name",repository="some-org-or-user/some-repo"} 1.0
```

#### github_actions_exporter_rate_limit_remaining

```
# TYPE github_actions_exporter_rate_limit_remaining gauge
# HELP github_actions_exporter_rate_limit_remaining Remaining calls left for the GitHub v3 REST API
```

Tracks the exporters usage of the GitHub API. Typical example:

```
github_actions_exporter_rate_limit_remaining 14819.0
```

The usage is updated in a separate thread against the actual remaining limit from GitHub (not just by passively inspecting response headers). This value should be accurate at the time it is recorded, but we update it at the end of the refresh cycle for repositories. That means that if we've started another refresh cycle, it may be slightly out of date at the point when you're viewing the metric.
