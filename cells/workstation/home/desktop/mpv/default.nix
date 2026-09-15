# mpv, ported from jarvis users/shared/gui/mpv (2026-09-15).
#
# Changes against jarvis:
# - hwdec nvdec-copy -> vaapi: penrose runs the iGPU only (gpu-intel.nix
#   ships intel-media-driver for exactly this). The dGPU is powered down.
# - K (motion interpolation) actually works: jarvis had the .vpy but stock
#   mpv (vapoursynthSupport = false) and no mvtools/ffms2 plugins, so the
#   filter failed to load. Here mpv-unwrapped is built with vapoursynth
#   support against `vapoursynth.withPlugins [mvtools ffms]`, whose patched
#   libvapoursynth autoloads $out/lib/vapoursynth -- the script's
#   `core.mv.*` / `core.ffms2.Source` resolve without LoadPlugin.
# - ao openal -> pipewire (layer-session.nix runs pipewire; openal was a
#   non-NixOS workaround).
# - dropped `vf = format=rgba`: an unconditional software RGBA convert on
#   every frame, undocumented since the first commit (edd27d3), and it defeats
#   hwdec (forces a readback). Nothing here needs RGB input.
# - mpv-hq alias stays (home.shellAliases -> zsh via deck).
{pkgs, ...}: let
  a4k = pkgs.anime4k;
  # Anime4K "Fast" presets, GLSL_Mac_Linux_Low-end/input.conf upstream.
  shaders = names: pkgs.lib.concatMapStringsSep ":" (n: "${a4k}/${n}.glsl") names;
  a4kBind = label: names: ''no-osd change-list glsl-shaders set "${shaders names}"; show-text "Anime4K: ${label}"'';
  pre = ["Anime4K_AutoDownscalePre_x2" "Anime4K_AutoDownscalePre_x4"];
  up = ["Anime4K_Upscale_CNN_x2_S"];

  vapoursynth = pkgs.vapoursynth.withPlugins [pkgs.vapoursynth-mvtools pkgs.ffms];
  mpv = pkgs.mpv.override {
    mpv-unwrapped = pkgs.mpv-unwrapped.override {
      inherit vapoursynth;
      vapoursynthSupport = true;
    };
  };
in {
  programs.mpv = {
    enable = true;
    package = mpv;
    config = {
      screenshot-format = "png";
      screenshot-directory = "~/Pictures/Screenshots";
      ao = "pipewire";
      audio-channels = "stereo";
      hwdec = "vaapi";
      vo = "gpu";
      gpu-context = "waylandvk";
      gpu-api = "vulkan";
    };
    profiles.hq = {
      profile = "high-quality";
      scale = "ewa_lanczossharp";
      cscale = "ewa_lanczossharp";
      tscale = "oversample";
      input-commands = "set user-data/current-profile \"High Quality profile\"";
    };
    bindings = {
      "K" = "vf toggle vapoursynth=${./motioninterpolation.vpy}";
      "p" = "show-text \"current profile: \${user-data/current-profile}\"";

      "CTRL+1" = a4kBind "Mode A (Fast)" (["Anime4K_Clamp_Highlights" "Anime4K_Restore_CNN_M" "Anime4K_Upscale_CNN_x2_M"] ++ pre ++ up);
      "CTRL+2" = a4kBind "Mode B (Fast)" (["Anime4K_Clamp_Highlights" "Anime4K_Restore_CNN_Soft_M" "Anime4K_Upscale_CNN_x2_M"] ++ pre ++ up);
      "CTRL+3" = a4kBind "Mode C (Fast)" (["Anime4K_Clamp_Highlights" "Anime4K_Upscale_Denoise_CNN_x2_M"] ++ pre ++ up);
      "CTRL+4" = a4kBind "Mode A+A (Fast)" (["Anime4K_Clamp_Highlights" "Anime4K_Restore_CNN_M" "Anime4K_Upscale_CNN_x2_M" "Anime4K_Restore_CNN_S"] ++ pre ++ up);
      "CTRL+5" = a4kBind "Mode B+B (Fast)" (["Anime4K_Clamp_Highlights" "Anime4K_Restore_CNN_Soft_M" "Anime4K_Upscale_CNN_x2_M"] ++ pre ++ ["Anime4K_Restore_CNN_Soft_S"] ++ up);
      "CTRL+6" = a4kBind "Mode C+A (Fast)" (["Anime4K_Clamp_Highlights" "Anime4K_Upscale_Denoise_CNN_x2_M"] ++ pre ++ ["Anime4K_Restore_CNN_S"] ++ up);
      "CTRL+0" = ''no-osd change-list glsl-shaders clr ""; show-text "GLSL shaders cleared"'';
    };
  };

  home.shellAliases.mpv-hq = "mpv --profile=hq";
}
