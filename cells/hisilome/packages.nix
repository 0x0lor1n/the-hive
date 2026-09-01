# Hísilómë's build outputs: the rendered site, and the library/station helper
# scripts.
#
# Was the blog's own flake.nix before iter 13 folded that repo in here. The
# wrappers exist so process-compose and the systemd units can invoke these by
# NAME with their dependencies pinned, rather than relying on the caller's PATH.
# rensa passes `system` as well as `inputs` and `cell`, so block files need an
# ellipsis. hive's signature was exactly `{ inputs, cell }`.
{
  inputs,
  cell,
  ...
}: let
  # `inputs.pkgs`, NOT `inputs.nixpkgs`. Under hive, `inputs.nixpkgs` arrived
  # already instantiated; under rensa it is the flake, and the instantiated set
  # comes from the root flake's `transformInputs`. deSystemize flattens
  # `.legacyPackages.<system>` onto it, so `inputs.nixpkgs.lib` still works and
  # `inputs.nixpkgs.hello` happens to as well -- but `writeShellApplication`
  # lives in stdenv/trivial-builders, so it is NOT present, and the failure is
  # a missing-attribute error at build time rather than at eval.
  pkgs = inputs.pkgs;
  # Only the files zola actually reads. NOT the whole flake source and not the
  # whole cell: music/ is 1.1 GB of gitignored FLAC, and radio/state/ is
  # rewritten every second by a running station -- either would make the site
  # derivation churn (and, through it, osgiliath's toplevel) on every edit.
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
  # The rendered site. Built on a workstation and pushed as a closure --
  # osgiliath has one vCPU and colmena's buildOnTarget is false.
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

  # NOT in the devShell: iosevka-bin is 426 MB and build-time only -- the site
  # serves the committed subsets. Use: nix run .#build-fonts
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
