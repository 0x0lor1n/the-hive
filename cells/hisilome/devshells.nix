# Development shell for the site and the radio station.
#
# Named `hisilome`, not `default`: cells/repo/devshells.nix owns `default`
# (flake tooling, colmena, secrets), and the two are genuinely separate
# concerns. Station work should not drag in agenix and QEMU, and host work
# should not drag in liquidsoap's 2.85 GiB closure.
#
#   nix develop .#hisilome
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

  # `dev [<cell>]` -- switch devshells. Same shared script the deploy shell
  # ships (nix/dev.sh); present here so `dev` (e.g. `dev` back to repo) works
  # from inside the station shell too.
  dev = pkgs.writeShellApplication {
    name = "dev";
    runtimeInputs = with pkgs; [git direnv coreutils];
    text = builtins.readFile "${inputs.self.outPath}/nix/dev.sh";
  };
in {
  hisilome = pkgs.mkShellNoCC {
    name = "hisilome";
    packages =
      (with pkgs; [
        zola
        ffmpeg
        flac
        icecast
        liquidsoap
        nginx
        process-compose
        watchexec
      ])
      ++ (with cell.packages; [
        tag-replaygain
        tag-album
        build-queue
        listener-count
      ])
      ++ [dev];

    shellHook = ''
      echo "zola build                                   generate the site into public/"
      echo "zola serve                                   live-reloading preview"
      echo "process-compose up -f process-compose.yaml   local stack: icecast+liquidsoap+nginx"
      echo "tag-replaygain music                         write ReplayGain tags (-n to preview)"
      echo "tag-album music                              write ALBUM tags from [bracket] prefixes"
      echo "build-queue music                            rebuild the play queue + schedule"
      echo
      echo "NOTE: run these from cells/hisilome/ -- the configs use relative paths."
      echo "dev            switch back to the deploy shell (repo)"
    '';
  };
}
