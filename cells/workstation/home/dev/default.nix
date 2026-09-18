# Developer tooling shared by both accounts: languages, editors, agent CLIs
# (claude-code, opencode — shared packages, per-home state stays under $HOME).
# Git identities are not here: they come from the encrypted per-role attrset
# (home/secrets.nix) and are wired in ../default.nix (programs.git.includes).
{...}: {
  imports = [./languages.nix ./agents.nix];
}
