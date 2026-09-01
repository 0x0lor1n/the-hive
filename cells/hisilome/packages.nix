# The rendered site and the station helper scripts, wrapped so process-compose
# and the systemd units run the same pinned builds.
{
  inputs,
  cell,
  ...
}: let
  pkgs = inputs.pkgs;
  # Exclude music/ (1.1 GB, gitignored) and radio/state/ (rewritten every
  # second by a running station) or the site derivation -- and through it the
  # host toplevel -- churns on every edit.
  src = builtins.path {
    path = ./.;
    name = "hisilome-src";
    filter = path: type: let
      rel = pkgs.lib.removePrefix (toString ./. + "/") (toString path);
    in
      !(pkgs.lib.hasPrefix "music" rel || pkgs.lib.hasPrefix "radio/state" rel);
  };

  mkScript = name: runtimeInputs:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text = builtins.readFile "${src}/bin/${name}.sh";
    };
in {
  site = pkgs.runCommand "hisilome-site" {} ''
    cp -r ${src} s
    chmod -R u+w s
    cd s
    ${pkgs.zola}/bin/zola build --output-dir $out
  '';

  tag-replaygain = mkScript "tag-replaygain" (
    with pkgs; [
      ffmpeg
      flac
      python3Packages.mutagen
      coreutils
      findutils
      gawk
    ]
  );

  # Not in process-compose: albums change with the library, not with the
  # station, and a boot-time rewrite would remux the m4a tracks every run.
  tag-album = mkScript "tag-album" (
    with pkgs; [
      ffmpeg
      flac
      python3Packages.mutagen
      coreutils
      findutils
      gawk
    ]
  );

  build-queue = mkScript "build-queue" (
    with pkgs; [
      ffmpeg
      coreutils
      findutils
      gawk
    ]
  );

  listener-count = mkScript "listener-count" (
    with pkgs; [
      curl
      coreutils
      gnused
      gawk
    ]
  );

  # Not in the devshell: iosevka-bin is 426 MB; the site serves the committed
  # subsets.
  build-fonts = pkgs.writeShellApplication {
    name = "build-fonts";
    runtimeInputs = [
      (pkgs.python3.withPackages (ps: [
        ps.fonttools
        ps.brotli
      ]))
      pkgs.nix
      pkgs.coreutils
    ];
    text = builtins.readFile "${src}/bin/build-fonts.sh";
  };
}
