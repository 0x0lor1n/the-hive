# Applied to every host.
{inputs, ...}: {pkgs, ...}: {
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
    # No global registry (network fetch on every bare `nixpkgs#` reference);
    # `nixpkgs` is pinned below to the exact input the system was built from.
    flake-registry = "";
  };

  # `nix run nixpkgs#foo` / `nix shell nixpkgs#foo` resolve to the flake.lock
  # revision: same store paths as the system, nothing new to download.
  nix.registry.nixpkgs.flake = inputs.nixpkgs;
  nix.nixPath = ["nixpkgs=${inputs.nixpkgs}"];

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
