# penrose-only. Muxless PRIME: i915 keeps scanout, Steam gets the four
# nvidia-offload variables so every child renders on the Quadro. Library in
# /state, not /persist: re-downloadable, keep it out of backups.
# nyx's luxtorpeda unpacks into $out/bin without a `steamcompattool` output;
# extraCompatPackages would see a dir with no compatibilitytool.vdf.
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
        # Mesa's device_select layer runs after NV_optimus and puts the i915
        # back at index 0, where fossilize (--device-index 0) and DXVK pick.
        NODEVICE_SELECT = "1";
      };
    };
    # x86_64_v3: the E3-1505M v6 has AVX2.
    extraCompatPackages = [
      pkgs.proton-cachyos_x86_64_v3
      pkgs.proton-ge-custom
      (asCompatTool pkgs.luxtorpeda)
    ];
    extest.enable = true;
  };
  hardware.graphics = {
    enable32Bit = true;
    # Inert until a game is launched with LOW_LATENCY_LAYER=1 %command%.
    extraPackages = [pkgs.low-latency-layer];
  };
  environment.systemPackages = [pkgs.mangohud_git];

  services.ananicy = {
    enable = true;
    package = pkgs.ananicy-cpp;
    rulesProvider = pkgs.ananicy-rules-cachyos_git;
  };

  # `users` form, unlike host-elster.nix: the account is in users.users
  # (layer-users-local), not NSS-only.
  environment.persistence."/state".users.${host.userName}.directories = [
    {
      directory = ".local/share/Steam";
      mode = "0700";
    }
  ];
}
