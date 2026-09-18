# dircolors: LS_COLORS for ls/eza/fd via `dircolors -b`. HM writes
# ~/.dir_colors and evals it from .zshrc (enableZshIntegration defaults on).
# No palette file, so this is dircolors' built-in default database.
{
  inputs,
  cell,
}: {...}: {
  programs.dircolors.enable = true;
}
