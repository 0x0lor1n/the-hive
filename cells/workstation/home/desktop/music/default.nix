# Music: mpd plays /srv/data/music (profiles/srv-data.nix) into PipeWire,
# rmpc is the TUI client. Ported from wochap/nix-config wm-addons/music,
# minus cava, the visualizer fifo/snd_aloop and YouTube Music.
#
# Bound in packages/dwl/config.h: Super+Alt+M opens rmpc in a floating foot
# (app_id "music", bypasses sesh/tmux); XF86 Play/Next/Prev/Stop go through
# playerctl, which reaches mpd via mpdris2. Closing rmpc leaves mpd playing.
#
# rmpc has no HM module on release-25.05. Its theme uses named ANSI colours,
# so foot's kanagawa palette already applies; config.ron only overrides a few
# keys, serde fills the rest from rmpc's defaults.
# State to persist: ~/.local/share/mpd (db, queue/state, playlists).
{pkgs, ...}: let
  musicDir = "/srv/data/music";

  # Fetches cover.jpg into album dirs that lack one; rmpc/mpd pick it up.
  music-covers = pkgs.writeShellApplication {
    name = "music-covers";
    runtimeInputs = [pkgs.sacad];
    text = ''sacad_r "$@" ${musicDir} 600 cover.jpg'';
  };
in {
  home.packages = [
    pkgs.rmpc
    pkgs.mpc
    pkgs.playerctl
    music-covers
  ];

  xdg.configFile."rmpc/config.ron".text = ''
    #![enable(implicit_some)]
    #![enable(unwrap_newtypes)]
    #![enable(unwrap_variant_newtypes)]
    (
        // .lrc files next to the tracks, same stem as the audio file
        lyrics_dir: "${musicDir}",
        scrolloff: 4,
        select_current_song_on_change: true,
        ignore_leading_the: true,
        enable_mouse: false,
        // Album Artists tab dropped: keys shift down, "7" stays a dead Search alias.
        keybinds: (
            global: {
                "4": SwitchToTab("Albums"),
                "5": SwitchToTab("Playlists"),
                "6": SwitchToTab("Search"),
            },
        ),
        // rmpc 0.11 example_config.ron tabs verbatim, minus Album Artists;
        // re-diff on an rmpc bump.
        tabs: [
            (
                name: "Queue",
                pane: Split(
                    direction: Horizontal,
                    panes: [
                        (
                            size: "35%",
                            pane: Split(
                                direction: Vertical,
                                panes: [
                                    (
                                        size: "100%",
                                        borders: "LEFT | RIGHT | TOP",
                                        border_symbols: Rounded,
                                        pane: Pane(AlbumArt)
                                    ),
                                    (
                                        size: "7",
                                        borders: "ALL",
                                        border_symbols: Inherited(parent: Rounded, top_left: "├", top_right: "┤",),
                                        border_title: [(kind: Text(" Lyrics "))],
                                        border_title_alignment: Right,
                                        pane: Pane(Lyrics)
                                    ),
                                ],
                            ),
                        ),
                        (
                            size: "65%",
                            pane: Split(
                                direction: Vertical,
                                panes: [
                                    (
                                        size: "3",
                                        borders: "ALL",
                                        border_symbols: Inherited(parent: Rounded, bottom_left: "├", bottom_right: "┤",),
                                        pane: Split(
                                            direction: Horizontal,
                                            panes: [
                                                (
                                                    size: "1",
                                                    pane: Pane(Empty())
                                                ),
                                                (
                                                    size: "100%",
                                                    pane: Pane(QueueHeader())
                                                ),
                                            ]
                                        )
                                    ),
                                    (
                                        size: "100%",
                                        borders: "LEFT | RIGHT | BOTTOM",
                                        border_symbols: Rounded,
                                        pane: Split(
                                            direction: Horizontal,
                                            panes: [
                                                (
                                                    size: "1",
                                                    pane: Pane(Empty())
                                                ),
                                                (
                                                    size: "100%",
                                                    pane: Pane(Queue)
                                                ),
                                            ]
                                        )
                                    ),
                                ],
                            )
                        ),
                    ],
                ),
            ),
            (
                name: "Directories",
                borders: "ALL",
                border_symbols: Rounded,
                pane: Split(
                    size: "100%",
                    direction: Vertical,
                    panes: [(pane: Pane(Directories), size: "100%", borders: "ALL", border_symbols: Rounded)],
                )
            ),
            (
                name: "Artists",
                borders: "ALL",
                border_symbols: Rounded,
                pane: Split(
                    size: "100%",
                    direction: Vertical,
                    panes: [(pane: Pane(Artists), size: "100%", borders: "ALL", border_symbols: Rounded)],
                )
            ),
            (
                name: "Albums",
                borders: "ALL",
                border_symbols: Rounded,
                pane: Split(
                    size: "100%",
                    direction: Vertical,
                    panes: [(pane: Pane(Albums), size: "100%", borders: "ALL", border_symbols: Rounded)],
                )
            ),
            (
                name: "Playlists",
                borders: "ALL",
                border_symbols: Rounded,
                pane: Split(
                    size: "100%",
                    direction: Vertical,
                    panes: [(pane: Pane(Playlists), size: "100%", borders: "ALL", border_symbols: Rounded)],
                )
            ),
            (
                name: "Search",
                borders: "ALL",
                border_symbols: Rounded,
                pane: Split(
                    size: "100%",
                    direction: Vertical,
                    panes: [(pane: Pane(Search), size: "100%", borders: "ALL", border_symbols: Rounded)],
                )
            ),
        ],
    )
  '';

  services.mpd = {
    enable = true;
    # albumart only probes cover.{png,jpg,webp}, hardcoded, no config knob;
    # the patch adds folder.* / front.*. Local build, re-check on mpd bumps.
    package = pkgs.mpd.overrideAttrs (old: {
      patches = (old.patches or []) ++ [./mpd-folder-art.patch];
    });
    musicDirectory = musicDir;
    network.listenAddress = "127.0.0.1";
    extraConfig = ''
      auto_update "yes"
      restore_paused "yes"

      audio_output {
        type "pipewire"
        name "PipeWire"
      }
    '';
  };

  # MPRIS bridge for mpd; playerctld makes playerctl target the last active player.
  services.mpdris2 = {
    enable = true;
    notifications = false;
  };
  services.playerctld.enable = true;
}
