# skim: the fuzzy finder behind Ctrl-T / Alt-C (and, via zsh-histdb-skim,
# Ctrl-R).
#
# enableZshIntegration stays off: zsh.nix sources skim's completion.zsh /
# key-bindings.zsh itself inside zvm_after_init, because they must load after
# zsh-vi-mode or vi mode eats the bindings.
{
  inputs,
  cell,
}: {
  lib,
  pkgs,
  ...
}: let
  r = inputs.cells.common.theme.roles;
  # One spec for two parsers: sk 5.4 (the widgets) and the skim 0.10.4 that
  # zsh-histdb-skim links for Ctrl-R. Each ignores the other's unknown
  # names: 5.4 wants `normal`, 0.10 wants `fg`. `empty` as base in both, so
  # nothing falls back to the built-in 256-cube theme.
  color = builtins.concatStringsSep "," (["empty"]
    ++ lib.mapAttrsToList (n: v: "${n}:#${v}") {
      normal = r.fg;
      fg = r.fg;
      bg = r.bg;
      hl = r.highlight;
      "fg+" = r.fg;
      "bg+" = r.selection;
      "hl+" = r.highlight;
      current_match_bg = r.selection;
      query = r.fg;
      prompt = r.focus;
      pointer = r.hover;
      marker = r.accent;
      spinner = r.info;
      info = r.muted;
      header = r.info;
      border = r.border;
      scrollbar = r.border;
    });
in {
  # Ctrl-R never sees SKIM_DEFAULT_OPTIONS; it reads this instead.
  home.sessionVariables.HISTDB_COLOR = color;

  programs.skim = {
    enable = true;
    enableBashIntegration = false;
    enableZshIntegration = false;

    defaultOptions = ["--color=${color}"];

    # fd instead of find for the widgets, hidden files included, .git skipped.
    fileWidgetCommand = "${pkgs.fd}/bin/fd --type f --hidden --follow --exclude .git";
    fileWidgetOptions = [
      "--preview '${pkgs.bat}/bin/bat --color=always --style=numbers --line-range=:500 {}'"
      "--preview-window=right:60%:wrap"
    ];
    changeDirWidgetCommand = "${pkgs.fd}/bin/fd --type d --hidden --follow --exclude .git";
    changeDirWidgetOptions = [
      "--preview '${pkgs.eza}/bin/eza --tree --color=always --icons --level=2 {}'"
      "--preview-window=right:60%"
    ];
  };
}
