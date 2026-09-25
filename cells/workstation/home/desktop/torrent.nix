# qBittorrent. The Qt palette comes from qt6ct (qt.nix); its own folder UI
# theme (config.json) only colours what the palette can't: torrent states,
# log levels, RSS read/unread.
#
# qBittorrent.conf is rewritten by the app on exit, so it is not a managed
# file: activation only sets the theme and save-path keys in place.
# State to persist: ~/.config/qBittorrent (settings),
# ~/.local/share/qBittorrent (BT_backup resume data, logs).
{
  config,
  lib,
  pkgs,
  theme,
  ...
}: let
  k = theme.roles;
  c = theme.colors;
  h = x: "#${x}";

  themeFile = "qBittorrent/themes/kanagawa/config.json";
  themePath = "${config.xdg.dataHome}/${themeFile}";
  # profiles/srv-data.nix: shared by both accounts, survives rollback.
  downloadDir = "/srv/data/torrents";

  colors = {
    "Log.TimeStamp" = h k.muted;
    "Log.Normal" = h k.fg;
    "Log.Info" = h k.focus;
    "Log.Warning" = h c.surimiOrange;
    "Log.Critical" = h k.urgent;
    "Log.BannedPeer" = h c.waveRed;

    "RSS.ReadArticle" = h k.muted;
    "RSS.UnreadArticle" = h k.fg;

    "TransferList.Downloading" = h k.success;
    "TransferList.StalledDownloading" = h c.autumnGreen;
    "TransferList.DownloadingMetadata" = h k.success;
    "TransferList.ForcedDownloadingMetadata" = h k.success;
    "TransferList.ForcedDownloading" = h k.success;
    "TransferList.Uploading" = h k.info;
    "TransferList.StalledUploading" = h c.dragonBlue;
    "TransferList.ForcedUploading" = h k.info;
    "TransferList.QueuedDownloading" = h k.highlight;
    "TransferList.QueuedUploading" = h k.highlight;
    "TransferList.CheckingDownloading" = h c.waveAqua2;
    "TransferList.CheckingUploading" = h c.waveAqua2;
    "TransferList.CheckingResumeData" = h c.waveAqua2;
    "TransferList.StoppedDownloading" = h k.muted;
    "TransferList.StoppedUploading" = h k.hover;
    "TransferList.Moving" = h c.waveAqua2;
    "TransferList.MissingFiles" = h c.peachRed;
    "TransferList.Error" = h k.urgent;
  };
in {
  home.packages = [pkgs.qbittorrent];

  # Merges into the mimeApps set in home/default.nix; magnet links from
  # Firefox go out through xdg-open to here.
  xdg.mimeApps.defaultApplications = {
    "application/x-bittorrent" = "org.qbittorrent.qBittorrent.desktop";
    "x-scheme-handler/magnet" = "org.qbittorrent.qBittorrent.desktop";
  };

  xdg.dataFile.${themeFile}.text = builtins.toJSON {inherit colors;};

  home.activation.qbittorrentSettings = lib.hm.dag.entryAfter ["writeBoundary"] ''
    conf=${lib.escapeShellArg "${config.xdg.configHome}/qBittorrent/qBittorrent.conf"}
    run mkdir -p "$(dirname "$conf")"
    ini="${pkgs.crudini}/bin/crudini --ini-options=nospace --set $conf"
    run $ini Preferences 'General\UseCustomUITheme' true
    run $ini Preferences 'General\CustomUIThemePath' ${lib.escapeShellArg themePath}
    run $ini BitTorrent 'Session\DefaultSavePath' ${downloadDir}
  '';
}
