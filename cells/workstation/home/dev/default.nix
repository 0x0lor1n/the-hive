# Developer tooling shared by both accounts: languages, editors, agent CLIs
# (claude-code, opencode — shared packages, per-home state stays under $HOME).
# Git identities are not here: they come from the encrypted per-role attrset
# (home/secrets.nix) and are wired in ../default.nix (programs.git.includes).
{config, ...}: {
  imports = [./languages.nix ./agents.nix];

  # Public repos' lefthook reads this; the agenix copy outlives the ephemeral
  # home (profiles/secrets.nix). Dangling on the VM, which the hook tolerates.
  xdg.configFile."gitleaks/personal.toml".source =
    config.lib.file.mkOutOfStoreSymlink "/run/agenix/gitleaks-personal";
}
