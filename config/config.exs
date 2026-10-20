# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

import Config

# IANA time zone data (compiled in, no runtime downloads) for households'
# local dates and weeks.
config :elixir, :time_zone_database, Tz.TimeZoneDatabase

# Self-hosted error tracking: errors are stored in our own Postgres and viewed
# at /admin/errors. Only resolved errors are pruned, after 30 days.
config :error_tracker,
  repo: Mealplan.Repo,
  otp_app: :mealplan,
  filter: MealplanWeb.Redact,
  plugins: [{ErrorTracker.Plugins.Pruner, max_age: to_timeout(day: 30)}]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  mealplan: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :mealplan, Mealplan.Mailer, adapter: Swoosh.Adapters.Local

# UUID keys by default in migrations, matching the schemas.
config :mealplan, Mealplan.Repo,
  migration_primary_key: [type: :binary_id],
  migration_foreign_key: [type: :binary_id]

# Configure the endpoint
config :mealplan, MealplanWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MealplanWeb.ErrorHTML, json: MealplanWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Mealplan.PubSub,
  live_view: [signing_salt: "PJD++BKn"]

config :mealplan, :mail_from, {"Mealplan", "mealplan@localhost"}

config :mealplan, :scopes,
  user: [
    default: true,
    module: Mealplan.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :binary_id,
    schema_table: :users,
    test_data_fixture: Mealplan.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

# General application configuration
config :mealplan,
  ecto_repos: [Mealplan.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Cooklang recipes and menus, so uploads can accept them (`mix deps.compile
# mime --force` after changing this).
config :mime, :types, %{
  "text/x-cooklang" => ["cook"],
  "text/x-cooklang-menu" => ["menu"]
}

# Keep secrets and magic-link tokens out of request logs.
config :phoenix, :filter_parameters, ["password", "token"]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Production uses SMTP, which needs no HTTP API client.
config :swoosh, :api_client, false

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.3",
  mealplan: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
