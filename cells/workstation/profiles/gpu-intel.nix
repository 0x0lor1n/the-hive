# Intel iGPU (i915) as the display device.
{
  inputs,
  cell,
}: {pkgs, ...}: {
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver # VAAPI (Broadwell+), what firefox/mpv ask for
    intel-compute-runtime # OpenCL, cheap to carry
  ];

  # btop's GPU panel reads the i915 PMU; upstream `make setcap`.
  security.wrappers.btop = {
    source = "${pkgs.btop}/bin/btop";
    owner = "root";
    group = "root";
    capabilities = "cap_perfmon,cap_dac_read_search+ep";
  };
}
