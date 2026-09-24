# bat: `cat` with syntax highlighting, plus `help <cmd>` piping --help
# through bat's help language.
{
  inputs,
  cell,
}: {
  lib,
  pkgs,
  ...
}: let
  # Upstream's own tmTheme: bg/fg/selection are already common/theme.nix's
  # bg/fg/selection, so it is taken as is rather than regenerated. delta
  # reads it too, through bat's cache (git.nix syntax-theme).
  kanagawaSrc = pkgs.fetchFromGitHub {
    owner = "rebelot";
    repo = "kanagawa.nvim";
    rev = "bb85e4bfc8d89b0e62c8fa53ccdd13d12e2f77b3";
    hash = "sha256-fMP4NUCKD1ZcNkaHy6SuNm020ECXpBOihGv2n1wyTN4=";
  };
in {
  programs.bat = {
    enable = true;
    themes.kanagawa = {
      src = kanagawaSrc;
      file = "extras/tmTheme/kanagawa.tmTheme";
    };
    config.theme = "kanagawa";
  };

  home.shellAliases.cat = "bat --plain";

  programs.zsh.initContent = lib.mkOrder 1000 ''
    # Call batman
    function help() {
      "$@" --help 2>&1 | bat --plain --language=help
    }
  '';
}
