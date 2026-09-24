# fzf: kept for the tools that shell out to it. Both shell integrations are
# off — skim covers the zsh widgets, and otherwise the two would fight over
# Ctrl-T/Alt-C.
{
  inputs,
  cell,
}: {...}: let
  r = inputs.cells.common.theme.roles;
  hex = c: "#${c}";
in {
  programs.fzf = {
    enable = true;
    enableBashIntegration = false;
    enableZshIntegration = false;
    # Replaces fzf's 256-cube defaults; the rest stays terminal-default.
    colors = {
      fg = hex r.fg;
      bg = hex r.bg;
      hl = hex r.highlight;
      "fg+" = hex r.fg;
      "bg+" = hex r.selection;
      "hl+" = hex r.highlight;
      query = hex r.fg;
      prompt = hex r.focus;
      pointer = hex r.hover;
      marker = hex r.accent;
      spinner = hex r.info;
      info = hex r.muted;
      header = hex r.info;
      border = hex r.border;
      scrollbar = hex r.border;
      gutter = hex r.bg;
    };
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
