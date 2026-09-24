# git, the account-agnostic half: aliases, merge tool, delta as the pager.
# Identity (user.name/email, includeIf per remote, ssh keys) is per account
# and stays in workstation/home/default.nix; HM merges both into one
# ~/.config/git/config.
#
# release-25.05 API: aliases/extraConfig and programs.git.delta (settings/
# programs.delta are 25.11+).
{
  inputs,
  cell,
}: {...}: let
  r = inputs.cells.common.theme.roles;
in {
  programs.git = {
    enable = true;

    aliases = {
      unstash = "stash pop";
      s = "status";
      tags = "tag -l";
    };

    extraConfig = {
      merge.tool = "nvimdiff";
      mergetool = {
        prompt = false;
        keepBackup = false;
      };
      "mergetool \"nvimdiff\"".layout = "LOCAL,BASE,REMOTE / MERGED";
    };

    delta = {
      enable = true;
      options = {
        side-by-side = true;
        file-modified-label = "modified:";
        # The tmTheme registered by bat.nix, found through bat's cache.
        syntax-theme = "kanagawa";
        # kanagawa.nvim's DiffText: changed words share one bg on both sides.
        minus-style = "syntax #${r.diffDelete}";
        minus-emph-style = "syntax #${r.diffText}";
        plus-style = "syntax #${r.diffAdd}";
        plus-emph-style = "syntax #${r.diffText}";
        line-numbers-minus-style = "#${r.urgent}";
        line-numbers-plus-style = "#${r.accent}";
        line-numbers-zero-style = "#${r.muted}";
      };
    };
  };
}
