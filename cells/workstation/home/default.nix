# The local user's home-manager config, consumed as a NixOS module via
# home-manager.users.<name> in profiles/layer-compositor.nix. utils.mkHome is
# broken upstream (bee.home), and standalone HM is not wanted anyway: the
# system and the home must switch together.
#
# Takes `host` (this host's globals entry) rather than a username: the
# username lives in the encrypted half of globals and cannot be an attribute
# name in a public file. Phase 4 of the test-vm port carries only the desktop;
# test-vm's coding-agents (llm-agents input with its own nixpkgs) and
# copy-files.nix are not ported.
{host}: {pkgs, ...}: {
  home.username = host.userName;
  home.homeDirectory = host.homeDir;
  # Must match system.stateVersion in nixosConfigurations.nix.
  home.stateVersion = "24.11";
  programs.home-manager.enable = true;
  # nixpkgs is unstable, home-manager is release-25.05: intentional.
  home.enableNixpkgsReleaseCheck = false;

  imports = [./desktop];

  # DWL's terminal keybind execs `foot` by name, so it must be on PATH.
  programs.foot = {
    enable = true;
    # 10 fits more on 1920x1080 than the default 12 and stays readable.
    settings.main.font = "monospace:size=10";
  };
}
