# virtio-gpu graphics for the QEMU guest.
#
# The generic seat/XKB variables are NOT here — they live in
# layer-session.nix, since they are not virtio-specific.
{
  inputs,
  cell,
}: {pkgs, ...}: {
  # mesa's virgl driver translates OpenGL to the host GPU via virtio-gpu;
  # DWL/wlroots only needs EGL+GLES2, not Vulkan.
  hardware.graphics.extraPackages = [pkgs.mesa];

  # Must reach the compositor itself, so not environment.variables (greetd's
  # session env is PAM-clean and never sees those).
  session.compositorEnvironment = {
    # virtio-gpu's cursor plane is unreliable under virgl.
    WLR_NO_HARDWARE_CURSORS = "1";
    # virtio-vga-gl's venus=true bypasses the legacy VGA geometry hints, so
    # the EDID wlroots sees may only list small modes — force the size the
    # QEMU window is opened with (ws-vm-run xres/yres). Real hardware has a
    # real EDID and must NOT have this.
    WLR_OUTPUT_DEFAULT_MODE = "1920x1080@60";
  };
}
