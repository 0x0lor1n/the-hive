# mpv.
#
# hwdec vaapi: these hosts run the iGPU only (gpu-intel.nix ships
# intel-media-driver for exactly this).
#
# K (motion interpolation) needs a vapoursynth-enabled mpv: mpv-unwrapped is
# built against `vapoursynth.withPlugins [mvtools ffms]`, whose patched
# libvapoursynth autoloads $out/lib/vapoursynth, so the script's `core.mv.*` /
# `core.ffms2.Source` resolve without LoadPlugin. Stock mpv has
# vapoursynthSupport = false and the filter fails to load.
#
# No `vf = format=rgba`: an unconditional software RGBA convert on every frame
# that also defeats hwdec by forcing a readback.
{
  pkgs,
  theme,
  ...
}: let
  r = theme.roles;
  hex = c: "#${c}";
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
      # OSD text, the seek/volume bar and list menus. Back colour keeps mpv's
      # default alpha (175 = AF).
      osd-color = hex r.fg;
      osd-outline-color = hex r.bgDim;
      osd-back-color = "#AF${r.bg}";
      osd-selected-color = hex r.highlight;
      osd-selected-outline-color = hex r.bgDim;
    };
    # The on-screen controller is osc.lua, which ignores osd-* and takes
    # #rrggbb only (anything else is warned about and dropped).
    scriptOpts.osc = {
      background_color = hex r.bg;
      timecode_color = hex r.fg;
      title_color = hex r.fg;
      time_pos_color = hex r.fg;
      time_pos_outline_color = hex r.bgDim;
      buttons_color = hex r.fg;
      small_buttonsL_color = hex r.fg;
      small_buttonsR_color = hex r.fg;
      top_buttons_color = hex r.fg;
      held_element_color = hex r.focus;
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
