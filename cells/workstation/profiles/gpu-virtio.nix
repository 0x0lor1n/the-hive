# virtio-gpu graphics. Was profiles/hardware-vm-gpu.nix.
#
# The generic seat/XKB variables are NOT here — they live in
# layer-session.nix, since they were never virtio-specific and both
# bare-metal machines need them too.
{
  inputs,
  cell,
}: {pkgs, ...}: {
  # mesa's virgl driver translates OpenGL to the host GPU via virtio-gpu;
  # DWL/wlroots only needs EGL+GLES2, not Vulkan.
  hardware.graphics.extraPackages = [pkgs.mesa];

  environment.variables = {
    # virtio-gpu's cursor plane is unreliable under virgl.
    WLR_NO_HARDWARE_CURSORS = "1";
    # virtio-vga-gl's venus=true bypasses the legacy VGA geometry hints, so
    # the EDID wlroots sees may only list small modes — force 1920x1080@60.
    # Real hardware has a real EDID and must NOT have this.
    WLR_OUTPUT_DEFAULT_MODE = "1920x1080@60";
  };
}
