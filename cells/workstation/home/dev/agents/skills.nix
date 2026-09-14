# Agent skills shared between claude-code and opencode (and, by hand,
# hermes: `ln -s` into ~/.hermes/skills). Each skill is a directory with a
# SKILL.md; some pull a package the skill shells out to. Store-backed (the
# scope reminder in port-jarvis-home: only nvim/tmux/zsh are live-edited).
{lib}: let
  skills = {
    nix-search = {
      dir = ./nix-search;
      packages = pkgs: [pkgs.nix-search-tv];
    };
    karpathy-guidelines = {
      dir = ./karpathy-guidelines;
      packages = _: [];
    };
    thermo-nuclear-code-quality-review = {
      dir = ./thermo-nuclear-code-quality-review;
      packages = _: [];
    };
  };
in {
  inherit skills;

  # home.file / xdg.configFile entries: <prefix>/<name>/SKILL.md.
  mkSkillFiles = prefix:
    lib.mapAttrs' (name: spec: {
      name = "${prefix}/${name}/SKILL.md";
      value.source = spec.dir + "/SKILL.md";
    })
    skills;

  packages = pkgs: lib.unique (lib.flatten (lib.mapAttrsToList (_: spec: spec.packages pkgs) skills));
}
