# Assembles stateDir and renders icecast.xml with the passwords.
{
  inputs,
  cell,
}: {
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.hisilome;
  runtime = cfg.stateDir;
  radioState = "${runtime}/radio/state";

  # Own store path per file. `inputs.self + "/cells/..."` would make the
  # toplevel depend on the whole flake source and re-push a 4 GiB closure on
  # every unrelated edit (measured).
  radioLiq = builtins.path {
    path = ../radio/radio.liq;
    name = "radio.liq";
  };
  icecastXml = builtins.path {
    path = ../radio/icecast.xml;
    name = "icecast.xml";
  };
in {
  config = lib.mkIf cfg.enable {
    # public/ is a store symlink: publishing is an atomic swap and zola never
    # runs on the target.
    systemd.services.hisilome-setup = {
      description = "Assemble the Hísilómë runtime directory";
      wantedBy = ["multi-user.target"];
      before = [
        "icecast.service"
        "liquidsoap.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -eu
        install -d -o ${cfg.user} -g ${cfg.group} -m 0755 "${runtime}" "${runtime}/radio"
        install -d -o ${cfg.user} -g ${cfg.group} -m 0755 "${radioState}" "${radioState}/logs"
        install -d -o ${cfg.user} -g ${cfg.group} -m 0750 "${runtime}/music"

        ln -sfn ${cfg.site} "${runtime}/public"
        ln -sfn ${radioLiq} "${runtime}/radio/radio.liq"

        # icecast.xml is rendered, not linked: it carries passwords, and store
        # files are world-readable. <webroot>/<adminroot> are re-pointed too;
        # the committed file pins a stale store path.
        #
        # colmena's deployment.keys land in /run/keys (tmpfs) and are gone after
        # a reboot until the next apply, so a value resolved on a previous boot
        # is kept on the persistent volume: key file, then previous boot, then
        # the committed dev value (loopback-only icecast; nginx proxies only
        # /stream.*).
        umask 077

        resolve() {  # $1 = key file or empty, $2 = env file, $3 = var name
          if [ -n "$1" ] && [ -r "$1" ]; then
            tr -d '\n' < "$1"
          elif [ -r "$2" ]; then
            sed -n "s/^$3=//p" "$2"
          else
            echo ""
          fi
        }

        SRC=$(resolve "${lib.optionalString (cfg.sourcePasswordFile != null) cfg.sourcePasswordFile}" \
                      "${radioState}/source.env" ICECAST_SOURCE_PASSWORD)
        ADM=$(resolve "${lib.optionalString (cfg.adminPasswordFile != null) cfg.adminPasswordFile}" \
                      "${radioState}/admin.env" ADMIN_PASSWORD)

        if [ -z "$SRC" ] || [ -z "$ADM" ]; then
          echo "hisilome-setup: WARNING - falling back to the committed dev password." >&2
          echo "  icecast is loopback-only so this is not remotely reachable, but run" >&2
          echo "  'colmena apply' to deliver the real credentials." >&2
        fi

        sed \
          -e "s#<webroot>.*</webroot>#<webroot>${pkgs.icecast}/share/icecast/web</webroot>#" \
          -e "s#<adminroot>.*</adminroot>#<adminroot>${pkgs.icecast}/share/icecast/admin</adminroot>#" \
          ${icecastXml} > "${runtime}/radio/icecast.xml"

        if [ -n "$SRC" ]; then
          sed -i \
            -e "s#<source-password>.*</source-password>#<source-password>$SRC</source-password>#" \
            -e "s#<relay-password>.*</relay-password>#<relay-password>$SRC</relay-password>#" \
            "${runtime}/radio/icecast.xml"
        else
          SRC=hackme
        fi
        if [ -n "$ADM" ]; then
          sed -i \
            -e "s#<admin-password>.*</admin-password>#<admin-password>$ADM</admin-password>#" \
            "${runtime}/radio/icecast.xml"
        else
          ADM=hackme
        fi

        # icecast cannot read a password from a descriptor, so on disk it is:
        # persistent volume, 0400, not in the store, not in git.
        printf 'ICECAST_SOURCE_PASSWORD=%s\n' "$SRC" > "${radioState}/source.env"
        printf 'ADMIN_PASSWORD=%s\nADMIN=admin:%s\n' "$ADM" "$ADM" > "${radioState}/admin.env"

        chown ${cfg.user}:${cfg.group} "${runtime}/radio/icecast.xml" \
          "${radioState}/source.env" "${radioState}/admin.env"
        chmod 0400 "${radioState}/source.env" "${radioState}/admin.env"
        chmod 0400 "${runtime}/radio/icecast.xml"
      '';
    };
  };
}
