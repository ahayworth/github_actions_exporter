FROM ruby:3.0.2

ENV APP_ENV=production
EXPOSE 9971

WORKDIR /app

COPY Gemfile* ./
RUN bundle install

RUN mkdir -p ./bin && mkdir -p ./lib
COPY ./bin/ ./bin/
COPY ./lib/ ./lib/

CMD ["/app/bin/github_actions_exporter"]
