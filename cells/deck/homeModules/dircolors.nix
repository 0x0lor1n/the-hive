# dircolors: LS_COLORS for ls/eza/fd via `dircolors -b`. HM writes
# ~/.dir_colors and evals it from .zshrc (enableZshIntegration defaults on).
#
# theme-debt: jarvis pulled the file from the catppuccin-dircolors input;
# that input and the flavour switch are gone, so this is dircolors' built-in
# default database until the theme pass wires a kanagawa one.
{
  inputs,
  cell,
}: {...}: {
  programs.dircolors.enable = true;
}
