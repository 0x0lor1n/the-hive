# btop: resource monitor. The GPU/CPU-wattage panels need cap_perfmon +
# cap_dac_read_search, which a home package cannot carry -- elster grants them
# through security.wrappers (profiles/host-elster.nix).
{
  inputs,
  cell,
}: {...}: {
  programs.btop.enable = true;
  # Setting anything here makes btop.conf a store symlink, so the layout is no
  # longer editable from the TUI -- it is a Nix setting from now on.
  # The theme is resolved by name from btop's own share/btop/themes, so there
  # is no file to derive from theme.palettes.
  programs.btop.settings = {
    color_theme = "kanagawa-wave";
    shown_boxes = "cpu mem net proc gpu0"; # gpu0 = box 5, open by default
  };
}
