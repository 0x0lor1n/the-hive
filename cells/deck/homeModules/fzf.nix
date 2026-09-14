# fzf: kept for the tools that shell out to it (skim covers the zsh widgets,
# so both shell integrations are off — otherwise fzf and skim would fight
# over Ctrl-T/Alt-C). Ported 1:1 from jarvis's users/shared/cli/fzf.nix.
#
# theme-debt: catppuccin.fzf (the --color line) dropped; stock fzf colours.
{
  inputs,
  cell,
}: {...}: {
  programs.fzf = {
    enable = true;
    enableBashIntegration = false;
    enableZshIntegration = false;
    defaultOptions = [
      "--no-height"
      "--walker-skip=.git,.direnv,node_modules"
      "--tabstop '2'"
      "--cycle"
      "--layout 'default'"
      "--no-separator"
      "--scroll-off '4'"
      "--prompt '❯ '"
      "--marker '❯'"
      "--pointer '❯'"
      "--scrollbar '🮉'"
      "--ellipsis '…'"

      # mappings
      "--bind 'ctrl-d:preview-half-page-down'"
      "--bind 'ctrl-u:preview-half-page-up'"
      "--bind 'ctrl-e:abort'"
      "--bind 'ctrl-y:accept'"
      "--bind 'ctrl-f:half-page-down'"
      "--bind 'ctrl-b:half-page-up'"
      "--bind '?:toggle-preview'"
    ];
  };
}
