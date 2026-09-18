# skim: the fuzzy finder behind Ctrl-T / Alt-C (and, via zsh-histdb-skim,
# Ctrl-R).
#
# enableZshIntegration stays off: zsh.nix sources skim's completion.zsh /
# key-bindings.zsh itself inside zvm_after_init, because they must load after
# zsh-vi-mode or vi mode eats the bindings.
{
  inputs,
  cell,
}: {pkgs, ...}: {
  programs.skim = {
    enable = true;
    enableBashIntegration = false;
    enableZshIntegration = false;

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
