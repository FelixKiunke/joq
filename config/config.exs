use Mix.Config

# NOTE: This config is only used for this project, it's not inherited when you use this library within an app.

if Mix.env == :test or Mix.env == :dev do
  config :joq,
    retry_strategy: {:immediately, 2}
end
