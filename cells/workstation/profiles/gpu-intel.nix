# Intel iGPU (i915) as the display device. Counterpart to gpu-virtio.nix:
# nothing here about cursors or output modes -- a real panel has a real EDID.
#
# penrose's Quadro M620 is muxless (no outputs): nouveau binds it as a
# render-only PRIME offload GPU (DRI_PRIME=1), D3cold via coreboot's _PR3.
{
  inputs,
  cell,
}: {pkgs, ...}: {
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver # VAAPI (Broadwell+), what firefox/mpv ask for
    intel-compute-runtime # OpenCL, cheap to carry
  ];

  # D3cold before (or without) nouveau; pcieport allows it on the root port.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x03[0-9]*", ATTR{power/control}="auto"
  '';

  # btop's GPU panel reads the i915 PMU; upstream `make setcap`.
  security.wrappers.btop = {
    source = "${pkgs.btop}/bin/btop";
    owner = "root";
    group = "root";
    capabilities = "cap_perfmon,cap_dac_read_search+ep";
  };
}
