# Site + station shell. Separate from repo's `default`: station work should not
# pull colmena/secrets, host work should not pull liquidsoap's 2.85 GiB closure.
{
  inputs,
  cell,
  ...
}: let
  pkgs = inputs.pkgs;

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
        process-compose
        watchexec
      ])
      ++ (with cell.packages; [
        tag-replaygain
        tag-album
        build-queue
        listener-count
        dev-nginx
      ])
      ++ [dev];

    shellHook = ''
      echo "zola build                                   generate the site into public/"
      echo "zola serve                                   live-reloading preview"
      echo "process-compose up -f process-compose.yaml   local stack: icecast+liquidsoap+nginx"
      echo "tag-replaygain music                         write ReplayGain tags (-n to preview)"
      echo "tag-album music                              write ALBUM tags from [bracket] prefixes"
      echo "build-queue music                            rebuild the play queue + schedule"
      echo "dev                                          back to the deploy shell"
      echo
      echo "NOTE: run these from cells/hisilome/ -- the configs use relative paths."
    '';
  };
}
