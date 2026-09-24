# neovim: LazyVim-based config, live-edited from /srv/the-hive/dotfiles/nvim
# (init.lua + lua/ + snippets/; lazy.nvim fetches plugins into
# ~/.local/share/nvim at first start, lazy-lock.json in dotfiles pins them).
# Plain `neovim` package, not programs.neovim: HM would generate its own
# init.lua and collide with the symlinked directory.
#
# The colorscheme is a lazy plugin, not a nix thing: switching nvim to
# kanagawa is a lua change in dotfiles/nvim/lua/custom/plugins/colorscheme/.
{
  inputs,
  cell,
}: {
  config,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    neovim
    tree-sitter
    # nvim-treesitter (main) compiles every grammar from source via `cc`;
    # without a C compiler in PATH no parser installs and nothing gets
    # highlighted (nix, lua, markdown, ...). gcc's wrapper provides `cc`.
    gcc
    ast-grep
    ripgrep
    # `trash-put`, shelled out to by neo-tree delete (plugins/editor.lua);
    # without it every delete from the file tree fails.
    trash-cli
  ];

  # Overrides NixOS's EDITOR=nano (programs.nano default): HM's zshenv sources
  # hm-session-vars after /etc/zshenv. git merge/commit read it too.
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink "/srv/the-hive/dotfiles/nvim";
}
