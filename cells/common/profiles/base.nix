# Base NixOS profile: locale, timezone, nix settings, SSH daemon.
# Applied to all hosts in the nixos cell.
{
  lib,
  pkgs,
  ...
}: {
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
    flake-registry = ""; # disable global registry lookups

    # Verbatim from xddxdd/nix-cachyos-kernel's flake.nix nixConfig;
    # configures the guest VM's nix daemon only — the host building the
    # image needs these set separately for a fast first build.
    extra-substituters = [
      "https://attic.xuyh0120.win/lantian"
      "https://cache.garnix.io"
      # Usually a miss unless pinning himmelblau's exact CI commit+nixpkgs.
      "https://himmelblau.cachix.org"
    ];
    extra-trusted-public-keys = [
      "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
      "himmelblau.cachix.org-1:yu8mq/NIBYsZHWzo4SOge97gpf02qugdZFT/JdRkswc="
    ];
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      # Kept on intentionally: the agenix-managed SSH key needs an
      # interactive TPM PIN to decrypt, which non-interactive agent
      # sessions can't supply — password auth is their supported path
      # (see `just ssh-vm-agent`).
      PasswordAuthentication = true;
    };
  };

  environment.systemPackages = with pkgs; [
    vim
    git
    sbctl # iter 4: sign+verify+status for Secure Boot
    fastfetch
  ];
}
