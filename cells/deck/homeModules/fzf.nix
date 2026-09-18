# fzf: kept for the tools that shell out to it. Both shell integrations are
# off — skim covers the zsh widgets, and otherwise the two would fight over
# Ctrl-T/Alt-C.
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
