# btop: resource monitor. The GPU/CPU-wattage panels need cap_perfmon +
# cap_dac_read_search, which a home package cannot carry -- elster grants them
# through security.wrappers (profiles/host-elster.nix).
{
  inputs,
  cell,
}: {...}: let
  r = inputs.cells.common.theme.roles;
  c = inputs.cells.common.theme.colors;
  # start/mid/end of one btop gradient.
  grad = name: s: m: e: ''
    theme[${name}_start]="#${s}"
    theme[${name}_mid]="#${m}"
    theme[${name}_end]="#${e}"
  '';
in {
  programs.btop.enable = true;
  # Setting anything here makes btop.conf a store symlink, so the layout is no
  # longer editable from the TUI -- it is a Nix setting from now on.
  programs.btop.settings = {
    color_theme = "kanagawa";
    shown_boxes = "cpu mem net proc gpu0"; # gpu0 = box 5, open by default
  };
  # Gradient families follow btop's bundled kanagawa-wave, with its
  # off-palette hexes swapped for the nearest palette colour.
  programs.btop.themes.kanagawa =
    ''
      theme[main_bg]="#${r.bg}"
      theme[main_fg]="#${r.fg}"
      theme[title]="#${r.fg}"
      theme[hi_fg]="#${r.urgent}"
      theme[selected_bg]="#${r.selection}"
      theme[selected_fg]="#${r.highlight}"
      theme[inactive_fg]="#${r.muted}"
      theme[graph_text]="#${r.muted}"
      theme[meter_bg]="#${r.border}"
      theme[proc_misc]="#${c.waveAqua2}"
      theme[cpu_box]="#${r.muted}"
      theme[mem_box]="#${r.muted}"
      theme[net_box]="#${r.muted}"
      theme[proc_box]="#${r.muted}"
      theme[div_line]="#${r.muted}"
    ''
    + grad "temp" r.success r.warning r.urgent
    + grad "cpu" r.success r.warning r.urgent
    + grad "process" r.success r.warning r.urgent
    + grad "free" c.samuraiRed c.autumnRed c.peachRed
    + grad "cached" c.boatYellow2 c.carpYellow c.roninYellow
    + grad "available" c.springViolet1 c.oniViolet c.oniViolet2
    + grad "used" c.dragonBlue c.crystalBlue c.springBlue
    + grad "download" c.crystalBlue c.springViolet1 c.oniViolet
    + grad "upload" c.boatYellow2 c.carpYellow c.samuraiRed;
}
