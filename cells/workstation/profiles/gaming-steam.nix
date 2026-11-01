# penrose-only. Muxless PRIME: the i915 keeps scanout, so Steam is started
# with the four variables the nvidia-offload wrapper exports and every child
# (Proton, the shader precompiler, the game) renders on the Quadro. No
# per-game `nvidia-offload %command%`. The client's CEF lands on the dGPU
# too, accepted.
#
# The library goes to /state, not /persist: shader caches, prefixes and games
# are re-downloadable and must stay out of the backups.
#
# nyx's proton-cachyos / luxtorpeda unpack into $out/bin and have no
# `steamcompattool` output. programs.steam.extraCompatPackages reads that
# output (makeSearchPathOutput falls back to $out), so without the adapter
# Steam gets a dir with no compatibilitytool.vdf and lists nothing.
# x86_64_v3: the E3-1505M v6 has AVX2.
{
  inputs,
  cell,
}: {
  pkgs,
  host,
  ...
}: let
  asCompatTool = tool:
    pkgs.runCommandLocal "${tool.name}-steamcompattool" {
      outputs = ["out" "steamcompattool"];
    } ''
      echo "${tool.name}: use programs.steam.extraCompatPackages, not systemPackages" > $out
      mkdir $steamcompattool
      ln -s ${tool}/bin/* $steamcompattool/
    '';
in {
  programs.steam = {
    enable = true;
    package = pkgs.steam.override {
      extraEnv = {
        __NV_PRIME_RENDER_OFFLOAD = "1";
        __NV_PRIME_RENDER_OFFLOAD_PROVIDER = "NVIDIA-G0";
        __GLX_VENDOR_LIBRARY_NAME = "nvidia";
        __VK_LAYER_NV_optimus = "NVIDIA_only";
      };
    };
    extraCompatPackages = map asCompatTool [
      pkgs.proton-cachyos_x86_64_v3
      pkgs.luxtorpeda
    ];
    extest.enable = true;
  };
  hardware.graphics.enable32Bit = true;

  # `users` form, unlike host-elster.nix: the account here is in users.users
  # (layer-users-local), not NSS-only.
  environment.persistence."/state".users.${host.userName}.directories = [
    {
      directory = ".local/share/Steam";
      mode = "0700";
    }
  ];
}
