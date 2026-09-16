# neovim: LazyVim-based config, live-edited from /srv/the-hive/dotfiles/nvim
# (init.lua + lua/ + snippets/; lazy.nvim fetches plugins into
# ~/.local/share/nvim at first start, lazy-lock.json in dotfiles pins them).
# Ported from jarvis's users/shared/tui/neovim. Plain `neovim` package, not
# programs.neovim: HM would generate its own init.lua and collide with the
# symlinked directory.
#
# theme-debt: the colorscheme is catppuccin (a lazy plugin, not a nix
# thing) reading CATPPUCCIN_FLAVOR/ACCENT with mocha/mauve defaults; the env
# vars are not exported here. Switching nvim to kanagawa is a lua change in
# dotfiles/nvim/lua/custom/plugins/colorscheme/.
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

  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink "/srv/the-hive/dotfiles/nvim";
}
