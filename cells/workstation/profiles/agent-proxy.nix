# pxpipe + Hermes system-wide: the Entra user has no home-manager. One pxpipe
# for all sessions: stateless, the API key rides in each request.
{
  inputs,
  cell,
}: {
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (inputs.cells.repo.packages) pxpipe hermes-agent rtk rtk-hermes-plugin;
  port = 47821;
  proxyHost = "pxpipe.anthropic.com";
  # Hermes (hermes_cli/runtime_provider.py) takes the endpoint for
  # `provider: anthropic` from model.base_url in config.yaml only -- not from
  # ANTHROPIC_BASE_URL -- and only when the hostname ends in .anthropic.com.
  # HERMES_CONFIG is not read either, so the config has to be written into
  # each user's ~/.hermes.
  model = {
    provider = "anthropic";
    base_url = "http://${proxyHost}:${toString port}/anthropic";
    default = "claude-opus-5-5";
  };
  pinned =
    lib.mapAttrs' (k: lib.nameValuePair "model.${k}") model
    // {
      "display.skin" = "kanagawa";
      # Context compaction rewrites the whole conversation into a summary;
      # haiku (hermes' default aux model) drops decisions and exact values.
      # Opus on a long context is slow, hence the timeout.
      "auxiliary.compression.provider" = "anthropic";
      "auxiliary.compression.model" = "claude-opus-5-5";
      "auxiliary.compression.timeout" = "300";
    };
  # Missing keys inherit hermes' gold default skin (skin_engine.py:831), so
  # every key it reads is set. Unreachable: diff line bgs are derived from
  # ui_error/ui_ok (agent/display.py:74-82), not winterRed/winterGreen.
  # JSON is YAML; the loader only needs `name`.
  hermesSkin = let
    r = inputs.cells.common.theme.roles;
    c = inputs.cells.common.theme.colors;
    hex = lib.mapAttrs (_: v: "#${v}");
    skin = pkgs.writeText "skin.json" (builtins.toJSON {
      name = "kanagawa";
      description = "Kanagawa Wave, from cells/common/theme.nix";
      colors = hex {
        background = r.bg;
        banner_border = r.focus;
        banner_title = r.highlight;
        banner_accent = r.accent;
        banner_dim = r.muted;
        banner_text = r.fg;
        ui_accent = r.focus;
        ui_label = r.info;
        ui_ok = r.success;
        ui_error = r.urgent;
        ui_warn = r.warning;
        ui_tool = r.hover;
        ui_thinking = r.muted;
        prompt = r.fg;
        input_rule = c.sumiInk6;
        response_border = r.focus;
        shell_dollar = r.info;
        diff_added = r.diffAdd;
        diff_removed = r.diffDelete;
        diff_added_word = r.success;
        diff_removed_word = r.urgent;
        syntax_string = r.accent;
        syntax_number = c.surimiOrange;
        syntax_keyword = r.hover;
        syntax_comment = r.muted;
        status_bar_bg = r.bgAlt;
        status_bar_text = r.fg;
        status_bar_strong = r.highlight;
        status_bar_dim = r.muted;
        status_bar_good = r.success;
        status_bar_warn = r.highlight;
        status_bar_bad = r.warning;
        status_bar_critical = r.urgent;
        session_label = r.info;
        session_border = r.muted;
        voice_status_bg = r.bgAlt;
        # Keys added by cells/repo/hermes-skin-pt-classes.patch.
        status_bar_title_bg = r.focus;
        status_bar_title_text = r.bg;
        status_bar_yolo = r.urgent;
        clarify_answer = r.success;
        voice_prompt = r.info;
        voice_recording = r.urgent;
        voice_processing = r.warning;
        selection_bg = r.selection;
        completion_menu_bg = r.bgAlt;
        completion_menu_current_bg = r.selection;
        completion_menu_meta_bg = r.bgAlt;
        completion_menu_meta_current_bg = r.selection;
      };
    });
    # The banner art's gold ladder, light to dark, onto a blue-violet one.
    artColors = pkgs.writeText "art-colors.json" (builtins.toJSON (hex {
      FFD700 = c.lightBlue;
      FFBF00 = c.springBlue;
      CD7F32 = c.crystalBlue;
      B8860B = c.springViolet1;
    }));
  in
    # The logo and caduceus are Rich markup with literal golds (banner.py:70,
    # 77); a skin replaces them only whole. Taken from the pinned hermes so
    # a bump that changes the art or its colours fails here, not silently.
    pkgs.runCommand "hermes-skin-kanagawa.yaml" {} ''
      ${lib.getExe pkgs.python3} ${./__hermes-skin-art.py} \
        ${hermes-agent}/lib/python3*/site-packages/hermes_cli/banner.py \
        ${skin} ${artColors} $out
    '';
  # Hermes rewrites config.yaml itself, so keys are merged via `config set`. The
  # Entra $HOME appears while the session opens: wait for it.
  seedHermes = pkgs.writeShellScript "hermes-seed-proxy" ''
    set -eu
    for _ in $(seq 1 120); do
      [ -d "$HOME" ] && break
      sleep 0.5
    done
    [ -d "$HOME" ] || { echo "no $HOME after 60s" >&2; exit 1; }
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: ''
        if [ "$(${lib.getExe hermes-agent} config get ${k} 2>/dev/null || true)" != ${lib.escapeShellArg v} ]; then
          ${lib.getExe hermes-agent} config set ${k} ${lib.escapeShellArg v}
        fi
      '')
      pinned)}

    mkdir -p "$HOME/.hermes/skins"
    ln -sfn ${hermesSkin} "$HOME/.hermes/skins/kanagawa.yaml"

    # skills/ and memories/ are shared by both accounts: /srv/agents/hermes
    # (srv-agents.nix). A real directory here is pre-migration per-user state;
    # leave it alone and let a human merge it, do not silently swap it out.
    for d in skills memories; do
      if [ -d "$HOME/.hermes/$d" ] && [ ! -L "$HOME/.hermes/$d" ]; then
        echo "~/.hermes/$d is a real directory, not linking /srv/agents/hermes/$d over it" >&2
      else
        ln -sfn "/srv/agents/hermes/$d" "$HOME/.hermes/$d"
      fi
    done

    mkdir -p "$HOME/.hermes/plugins"
    # rtk-rewrite: rtk's pre_tool_call rewrite. herdr-agent-state: session id
    # to the herdr pane (packages.nix herdr-integrations). A real directory
    # here is a hand-run `rtk init` / `herdr integration install` of some
    # other version; ours is the pinned one.
    for p in rtk-rewrite=${rtk-hermes-plugin} herdr-agent-state=${cell.packages.herdr-integrations}/hermes; do
      name=''${p%%=*}
      [ -d "$HOME/.hermes/plugins/$name" ] && [ ! -L "$HOME/.hermes/plugins/$name" ] && rm -rf "$HOME/.hermes/plugins/$name"
      ln -sfn "''${p#*=}" "$HOME/.hermes/plugins/$name"
      enabled=$(${lib.getExe hermes-agent} config get plugins.enabled 2>/dev/null || true)
      if ! printf '%s\n' "$enabled" | grep -qx -- "- $name"; then
        rest=$(printf '%s\n' "$enabled" | sed -n 's/^- \(.*\)$/"\1",/p' | tr -d '\n')
        ${lib.getExe hermes-agent} config set plugins.enabled "[''${rest}\"$name\"]"
      fi
    done
  '';
in {
  environment.systemPackages = [
    hermes-agent
    rtk
  ];

  environment.variables = {
    # nixq (in the agents' PATH) must exec exactly the client the system was
    # built with, not "first nix on PATH that isn't me".
    NIXQ_REAL_NIX = "${config.nix.package}/bin/nix";
    RTK_TELEMETRY_DISABLED = "1";
  };

  systemd.services.pxpipe = {
    description = "pxpipe: Anthropic loopback proxy";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      ExecStart = "${lib.getExe pxpipe} -port ${toString port}";
      Restart = "on-failure";
      RestartSec = 2;
      DynamicUser = true;
      # Nothing on disk, nothing to reach but the loopback listener and
      # api.anthropic.com.
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      RestrictAddressFamilies = ["AF_INET" "AF_INET6"];
      CapabilityBoundingSet = "";
    };
  };

  networking.hosts."127.0.0.1" = [proxyHost];

  # llm-agents builds every package daily into its own cache; without it a
  # bump compiles hermes' Rust/Python deps and bun bundles locally.
  nix.settings = {
    extra-substituters = ["https://cache.numtide.com"];
    extra-trusted-public-keys = ["niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="];
  };

  # Per-user: every login (local user over ssh/greetd, Entra user on seat0)
  # gets model.* pointed at the proxy. Idempotent, so a no-op on later logins.
  # !@system: greeter (uid 999, HOME=/var/empty) also reaches default.target.
  systemd.user.services.hermes-seed-proxy = {
    description = "Point ~/.hermes/config.yaml at the pxpipe proxy, enable the rtk plugin, link shared skills/memories";
    wantedBy = ["default.target"];
    unitConfig.ConditionUser = "!@system";
    path = [pkgs.coreutils pkgs.gnugrep pkgs.gnused];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = seedHermes;
      TimeoutStartSec = "180s";
    };
  };
}
