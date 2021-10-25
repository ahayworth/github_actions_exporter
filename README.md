## github_actions_exporter

This exporter tracks GitHub Actions workflow runs against a user or organization's repositories. Notable features:

- Supports Personal Access Token (PAT) or GitHub App authentication
- Aggressively caches responses and implements [conditional requests](https://docs.github.com/en/rest/overview/resources-in-the-rest-api#conditional-requests) to minimize API usage.
- Supports a variable refresh intervals to best match your Prometheus scrape duration or other requirements

## Getting started

Build the docker image (`docker build`) or pull the image from GitHub's registry:

```
TODO: write me
```

Configuration can be supplied as command line switches, or via environment variables:

```
Usage: github_actions_exporter --organization ORG --repos LIST,OF,REPOS

All options may be specified as a CLI switch, or an environment variable with the prefix 'GITHUB_ACTIONS_EXPORTER_'
For example, '--user foo' may instead be specified in the environment as 'GITHUB_ACTIONS_EXPORTER_USER=foo'.
CLI switches take priority over environment variables.

        --log-level LEVEL            Default: info
        --user USER                  GitHub user to scan. --user or --organization must be provided, but not both.
        --organization ORGANIZATION  GitHub organization to scan. --user or --organization must be provided, but not both.
        --repos REPOS                Comma-separated list of repositories. If none is provided, all will be scanned
        --interval INTERVAL          Seconds to sleep between scans
        --token TOKEN                GitHub token for authentication. --token or --pem-file must be provided, but not both.
        --pem-file FILE              Github App PEM file for authentication. --token or --pem-file must be provided, but not both.
        --installation-id ID         GitHub App installation ID for authentication.
        --app-id ID                  GitHub App ID for authentication.
```

Then, run the image:

```
docker run -e GITHUB_ACTIONS_EXPORTER_ORGANIZATION=foo -e GITHUB_ACTIONS_EXPORTER_TOKEN=bar -p 9978:9978 github_actions_exporter:latest
```

Metrics will be exposed on `http://localhost:9978` by default.

## Roadmap

- [ ] Implement `--repositories` flag
- [ ] Implement GitHub App authentication refresh
- [ ] Add tests
- [ ] Clean up threading code and move out of the `CLI` namespace
- [ ] Implement worker-pool paradigm to limit resource consumption
- [ ] Implement better finished job tracking
- [ ] Add `--port` option
- [ ] Implement billing stats
- [ ] Implement organization runner stats
- [ ] Improve error handling throughout

Some nice-to-haves:
- [ ] Silence Faraday warnings
- [ ] Clean up logging code
- [ ] Add stats about the exporter itself
- [ ] Add tracing support
- [ ] Use a better webserver

## Development

You'll need a working ruby installation - we've tested at v3.0.2 but it's likely that older versions will work.

1. `bundle`

If you want to set up solargraph (recommended!), then you'll need to:

1. `bundle exec solargraph download-core`
2. `bundle exec solargraph bundle`

Then configure your editor to use it.

