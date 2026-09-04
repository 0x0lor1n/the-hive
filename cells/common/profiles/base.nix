# Applied to every host.
{pkgs, ...}: {
  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "root"
      "@wheel"
    ];
    auto-optimise-store = true;
    flake-registry = "";
  };

  services.openssh.enable = true;

  environment.systemPackages = with pkgs; [
    vim
    git
    fastfetch
  ];

  # `cd` into the repo checkout loads the devshell via .envrc; nix-direnv
  # caches the eval so prompts stay fast.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
