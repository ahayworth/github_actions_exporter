FROM ruby:3.0.2

ENV APP_ENV=production
EXPOSE 9971

RUN adduser gha-exporter
USER gha-exporter

WORKDIR /app

COPY --chown=gha-exporter Gemfile* ./
RUN bundle install

RUN mkdir -p ./bin && mkdir -p ./lib
COPY --chown=gha-exporter ./bin/ ./bin/
COPY --chown=gha-exporter ./lib/ ./lib/

CMD ["/app/bin/github_actions_exporter"]
