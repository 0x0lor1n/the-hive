# lazygit: git TUI, diffs rendered through delta (git.nix enables delta
# globally).
{
  inputs,
  cell,
}: {...}: let
  r = inputs.cells.common.theme.roles;
in {
  programs.lazygit = {
    enable = true;
    # Unset, lazygit hashes each author name into a truecolor off the palette.
    settings.gui.authorColors."*" = "#${r.info}";
    settings.git = {
      # NOTE: camelCase matters. lazygit parses with yaml.v3, which is
      # case-sensitive and silently ignores unknown keys -- the old
      # `autofetch` spelling was a no-op and autofetch was actually enabled.
      autoFetch = false;
      # Renamed from `git.pagers` (item key `pager` -> `command`) in lazygit 0.61+.
      # `type` defaults to "stdinFilter", which is what delta needs, so it's omitted.
      diffRenderers = [
        {
          command = "delta --paging=never --line-numbers --hyperlinks --hyperlinks-file-link-format=\"lazygit-edit://{path}:{line}\"";
          colorArg = "always";
        }
      ];
    };
  };
}
