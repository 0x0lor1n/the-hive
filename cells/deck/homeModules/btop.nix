# btop: resource monitor. The GPU/CPU-wattage panels need cap_perfmon +
# cap_dac_read_search, which a home package cannot carry -- elster grants them
# through security.wrappers (profiles/host-elster.nix).
{
  inputs,
  cell,
}: {...}: {
  programs.btop.enable = true;
}
