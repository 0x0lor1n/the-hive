# tor with obfs4 bridges. Personal-account only (see ./default.nix).
#
# A user-level torrc + tor-start/stop/status helpers rather than services.tor:
# raised on demand, not a daemon on every boot, and the bridge list is the
# user's own. The obfs4 binary is `lyrebird` in nixpkgs' obfs4 package. Geoip
# files come from tor-browser's bundle so the ExitNodes country filter has
# data to work with.
{
  config,
  pkgs,
  ...
}: {
  xdg.configFile."tor/torrc".text = ''
    ExitNodes {ch}
    StrictNodes 1

    AvoidDiskWrites 1

    ClientTransportPlugin obfs4 exec ${pkgs.obfs4}/bin/lyrebird

    GeoIPFile ${pkgs.tor-browser}/share/tor-browser/TorBrowser/Data/Tor/geoip
    GeoIPv6File ${pkgs.tor-browser}/share/tor-browser/TorBrowser/Data/Tor/geoip6

    UseBridges 1
    Bridge obfs4 92.252.94.252:8080 02F00A33017A24E99112E5CA498AECD204F913F3 cert=eWfCYOE/3kdmDpYy/tT0CuKI01dWKY6BtSAMSu0uuD4ixo7RE4/av+0fNjw4sbZmORLKVQ iat-mode=0
    Bridge obfs4 185.177.207.204:11204 B6937CCDFFE05546B607A12003DA69F8136DD94F cert=ZRe3CHqlwsiJXeKVbLkpM3kAAo+JQQw0sHJBoGBjv2KDI2iibvPNoSanIjVYlqDuxntzNg iat-mode=1
    Bridge obfs4 57.128.57.245:3099 D655AC9C21147BB62C781149150F0E723C4F8FBC cert=fnU2eGPmE6L53eXZf/29d1JloUD2XI/4KHNImTquPr/eBvkrOuuutIlpwvJsZTV1NvZ4aw iat-mode=0
    Bridge obfs4 46.226.107.235:57180 93BD2E597D164D9FE9C74BF3E0F68531AC17EFB2 cert=lkV0hpUCIEEpU1nIFGnBJoabeXn0BFykm3NIf4an09Kq8nTK+qv6Z3A1i3Rkkc3hGMoqSA iat-mode=0

    SocksPort 9050

    ControlPort 9051
    CookieAuthentication 1

    Sandbox 0
  '';

  home.packages = with pkgs; [
    tor
    obfs4
    nyx
    proxychains
    tor-browser

    (writeShellScriptBin "tor-start" ''
      exec ${tor}/bin/tor -f ${config.xdg.configHome}/tor/torrc
    '')
    (writeShellScriptBin "tor-stop" ''
      pkill -x tor
    '')
    (writeShellScriptBin "tor-status" ''
      if pgrep -x tor >/dev/null; then
        echo "Tor is running (PID: $(pgrep -x tor))"
        exec ${nyx}/bin/nyx
      else
        echo "Tor is not running"
      fi
    '')
  ];
}
