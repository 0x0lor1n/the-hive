# Firefox (stable) hardened by Phoenix, as a SYSTEM package: the browser is
# the Entra account's daily driver, and Entra users never get a home.packages
# profile (see layer-compositor.nix). Replaces the old programs.librewolf +
# nur addons setup (decision 2026-09-14).
#
# Phoenix has two halves:
#   1. the wrapper: pkgs.withPhoenix = firefox.override { extraPoliciesFiles;
#      extraPrefsFiles } -- bakes policies.json + phoenix.cfg into the
#      package. pkgs already carries phoenix's overlay (nixosConfigurations.nix
#      extends it there because a module's nixpkgs.overlays does not reach a
#      pre-instantiated pkgs), so this is done by hand via programs.firefox.
#      package, and the module's own overlay hook is turned off.
#   2. the NixOS module: /etc/firefox/phoenix/{specs,assets} (phoenix.cfg
#      lockPrefs autoadmin.global_config_url to the specs file), MOZ_*
#      environment and programs.firefox.policies read from its policies.json,
#      which the NixOS firefox module writes to /etc/firefox/policies/ -- on
#      Linux that path wins over the package's distribution/policies.json.
#      Imported as-is for that. Its /etc/firefox/defaults/pref/phoenix.js is
#      dead weight here (nixpkgs firefox reads prefs from its own libDir);
#      the wrapper's mozilla.cfg carries phoenix.cfg instead.
# Our own policies (search engines, addons) merge into the same
# programs.firefox.policies attrset; Phoenix's SearchEngines defaults are
# mkForce'd since the module system cannot merge two scalars.
{inputs, ...}: {
  pkgs,
  lib,
  ...
}: let
  amo = id: "https://addons.mozilla.org/firefox/downloads/latest/${id}/latest.xpi";
  # Same 8 addons jarvis pinned through nur (rycee.firefox-addons), by AMO id.
  # normal_installed: installed, user may disable; Phoenix already forces
  # uBlock Origin and Multi-Account Containers the same way.
  addon = id: {
    installation_mode = "normal_installed";
    install_url = amo id;
  };
  engine = {
    name,
    url,
    alias ? null,
    description ? name,
  }:
    {
      Name = name;
      URLTemplate = url;
      Method = "GET";
      Description = description;
    }
    // lib.optionalAttrs (alias != null) {Alias = alias;};
in {
  imports = [inputs.phoenix.nixosModules.default];

  programs.firefox = {
    enable = true;
    package = pkgs.withPhoenix pkgs.firefox;
    # The module's overlay is what would apply withPhoenix to pkgs.firefox --
    # done above instead, so leave it nothing to patch.
    phoenix.firefoxPackages = [];

    policies = {
      ExtensionSettings = {
        "{b86e4813-687a-43e6-ab65-0bde4ab75758}" = addon "localcdn-fork-of-decentraleyes";
        "wappalyzer@crunchlabz.com" = addon "wappalyzer";
        "addon@darkreader.org" = addon "darkreader";
        "@contain-google" = addon "google-container";
        "jid1-Om7eJGwA1U8Akg@jetpack" = addon "octotree";
        "{a8332c60-5b6d-41ee-bfc8-e9bb331d34ad}" = addon "surfingkeys_ff";
        "{73a6fe31-595d-460b-a920-fcc0f8843232}" = addon "noscript";
        # uBlock Origin: Phoenix already normal_installed it.

        # Entra SSO (silent PRT cookie for login.microsoftonline.com through
        # himmelblau-broker). The himmelblau module already wires the native
        # messaging host (programs.firefox.nativeMessagingHosts) and pins
        # the webextension via Extensions.Install at v1.7.1. That release has
        # a Firefox-only advisory (GHSA-g9vc-5j77-f2cm, fixed in 1.10.2) and
        # Extensions.Install never updates a GitHub-hosted xpi, so install it
        # here instead, force_installed so the user cannot lose it. The
        # native side (himmelblau's rust_sso) is protocol-compatible: the
        # commands are getVersion/getAccounts/acquirePrtSsoCookie/
        # acquireTokenSilently in both.
        "linux-entra-sso@example.com" = {
          installation_mode = "force_installed";
          install_url = "https://github.com/siemens/linux-entra-sso/releases/download/v1.10.2/linux_entra_sso-1.10.2.xpi";
          default_area = "navbar";
        };
      };
      # ...and neutralise the module's older copy (see above).
      Extensions.Install = lib.mkForce [];

      # SearchEngines is a release-channel policy since Fx139 (this pin: 154).
      # Phoenix removes Google/Bing/DDG builtins and adds its DDG/Mojeek/
      # Startpage/SearXNG set; its Default is overridden to jarvis's 4get.
      SearchEngines = {
        Default = lib.mkForce "4get";
        DefaultPrivate = lib.mkForce "4get";
        Add = [
          (engine {
            name = "4get";
            url = "https://4get.dcs0.hu/web?s={searchTerms}&scraper=google_cse&nsfw=yes&country=ch";
          })
          (engine {
            name = "GitHub";
            alias = "gh";
            url = "https://github.com/search?q={searchTerms}&type=repositories";
          })
          (engine {
            name = "Nix Packages";
            alias = "np";
            url = "https://search.nixos.org/packages?channel=unstable&query={searchTerms}";
          })
          (engine {
            name = "Nix & Home-Manager options";
            alias = "no";
            url = "https://mynixos.com/search?q={searchTerms}";
          })
          (engine {
            name = "Nix library";
            alias = "nl";
            url = "https://noogle.dev/q?term={searchTerms}";
          })
          (engine {
            name = "Wikipedia (en)";
            alias = "wen";
            url = "https://en.wikipedia.org/w/index.php?search={searchTerms}";
          })
          (engine {
            name = "Wikipedia (ru)";
            alias = "wru";
            url = "https://ru.wikipedia.org/w/index.php?search={searchTerms}&go=%D0%9F%D0%B5%D1%80%D0%B5%D0%B9%D1%82%D0%B8";
          })
        ];
      };
    };

    # jarvis's librewolf `settings`, as defaultPref so they stay editable in
    # about:config. Appended to mozilla.cfg AFTER phoenix.cfg (the NixOS module
    # concatenates old.extraPrefsFiles ++ autoConfig), so they win over
    # Phoenix's sanitize-on-shutdown defaults -- the whole point: keep
    # cookies/cache/session across restarts, restore the previous session.
    # The Preferences *policy* would not accept privacy.clearOnShutdown_v2.*
    # (allow-listed prefixes only), hence autoconfig and not `preferences`.
    autoConfig = ''
      defaultPref("privacy.clearOnShutdown_v2.cache", false);
      defaultPref("privacy.clearOnShutdown_v2.cookiesAndStorage", false);
      defaultPref("privacy.clearOnShutdown_v2.browsingHistoryAndDownloads", false);
      defaultPref("privacy.sanitize.sanitizeOnShutdown", false);
      defaultPref("privacy.sanitize.pending", "[]");
      defaultPref("browser.startup.page", 3);
      defaultPref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
      defaultPref("privacy.resistFingerprinting.exemptedDomains", "claude.ai");
      // linux-entra-sso is MV3: since Fx 127 its host_permissions
      // (login.microsoftonline.com) are NOT granted at install, the user has
      // to click "(enable)" in the addon popup -- which is unreadable here
      // (2026-09-16), so the PRT cookie header never got injected. Grant
      // origin permissions at install time again, MV2-style. Only affects
      // installs after this lands; for an existing profile toggle it once in
      // about:addons -> Linux Entra SSO -> Permissions.
      lockPref("extensions.originControls.grantByDefault", true);
    '';
  };
}
