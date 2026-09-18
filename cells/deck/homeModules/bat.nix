# bat: `cat` with syntax highlighting, plus `help <cmd>` piping --help
# through bat's help language.
{
  inputs,
  cell,
}: {lib, ...}: {
  programs.bat.enable = true;

  home.shellAliases.cat = "bat --plain";

  programs.zsh.initContent = lib.mkOrder 1000 ''
    # Call batman
    function help() {
      "$@" --help 2>&1 | bat --plain --language=help
    }
  '';
}
