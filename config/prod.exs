use Mix.Config

config :xperiments, Xperiments.Endpoint,
  http: [port: {:system, "PORT", "8080"}],
  url: [host: {:system, "HOST", "xperiments.wetransfer.net"}, port: 80],
  cache_static_manifest: "priv/static/manifest.json",
  server: true,
  root: ".",
  version: Mix.Project.config[:version]

config :xperiments, :cors,
  origin: ~r/http(s)?.*wetransfer\d?\.com|http(s)?.*wtd0\d?\.com|http(s)?.*wetransferbeta\.com$/

config :xperiments, :js_config,
  reporting_url: "https://analytics.google.com/analytics/web/?authuser=1#my-reports/sT3DgjPiSoqc8N7ffF5E-w/a11792855w62566690p64155208/%3F_r.tabId%3D460/"

# Do not print debug messages in production
config :logger, level: :info

config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  redirect_uri: {:system, "GOOGLE_OAUTH_CALLBACK"}

config :xperiments, Xperiments.Endpoint,
  secret_key_base: {:system, "SECRET_KEY_BASE"}

config :guardian, Guardian,
  secret_key: {:system, "SECRET_KEY_BASE"}

config :xperiments, Xperiments.Repo,
  adapter: Ecto.Adapters.Postgres,
  url: {:system, "DB_URL"},
  pool_size: 20
