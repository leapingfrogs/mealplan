{ pkgs, lib, config, ... }:

let
  # Erlang/Elixir versions are declared once in .tool-versions, which CI
  # (erlef/setup-beam) and the Dockerfile also read. nixpkgs only offers one
  # patch release per minor, so we select the package set here and warn on
  # entering the shell if it drifts from .tool-versions.
  beam = pkgs.beam.packages.erlang_29;
  elixir = beam.elixir_1_20;

  toolVersions = lib.listToAttrs (map
    (line:
      let parts = lib.splitString " " line;
      in lib.nameValuePair (lib.head parts) (lib.last parts))
    (lib.filter (line: line != "")
      (lib.splitString "\n" (builtins.readFile ./.tool-versions))));

  wantedElixir = lib.head (lib.splitString "-" toolVersions.elixir);
  versionDrift =
    toolVersions.erlang != beam.erlang.version || wantedElixir != elixir.version;

  phxNewVersion = "1.8.15";
in
{
  languages.elixir = {
    enable = true;
    package = elixir;
    lsp.package = beam.expert;
  };

  packages = with pkgs; [
    jujutsu
    gh
    just
    inotify-tools # file watching for Phoenix live reload
    hadolint # Dockerfile linting
    actionlint # GitHub Actions workflow linting
    trivy # container image scanning
    nodejs # commitlint (Conventional Commits) via npx
  ];

  # Keep Mix/Hex archives and caches per-project instead of in ~/.mix.
  env.MIX_HOME = "${config.devenv.state}/mix";
  env.HEX_HOME = "${config.devenv.state}/hex";
  env.ERL_AFLAGS = "-kernel shell_history enabled";

  tasks."mealplan:install-phx-new" = {
    exec = ''
      mix local.hex --force --if-missing
      mix local.rebar --force --if-missing
      mix archive.install hex phx_new ${phxNewVersion} --force
    '';
    status = "mix phx.new --version 2>/dev/null | grep -q '${phxNewVersion}'";
    before = [ "devenv:enterShell" ];
  };

  enterShell = lib.optionalString versionDrift ''
    echo "warning: nixpkgs provides Erlang ${beam.erlang.version} / Elixir ${elixir.version}," >&2
    echo "         but .tool-versions pins Erlang ${toolVersions.erlang} / Elixir ${wantedElixir}." >&2
    echo "         Update .tool-versions (and CI/Docker) or adjust devenv.nix." >&2
  '';
}
