[
  import_deps: [:ecto, :ecto_sql, :phoenix, :error_tracker],
  subdirectories: ["priv/*/migrations"],
  plugins: [Phoenix.LiveView.HTMLFormatter, Styler],
  # Styler otherwise defaults to 122; keep the Elixir formatter default.
  line_length: 98,
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"]
]
