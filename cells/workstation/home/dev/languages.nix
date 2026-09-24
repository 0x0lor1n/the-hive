# Language toolchains: plain package lists, nothing account-specific. Grouped
# in one file because ten 5-line modules were more directory than content.
{
  lib,
  pkgs,
  ...
}: let
  # Single source of truth for the Python version: the built env and the
  # site-packages path exported to Neovim (lang-python.lua) both follow it.
  pythonPkg = pkgs.python311;
  python-final = pythonPkg.withPackages (_ps: []);
  python-site-packages = "${python-final}/${pythonPkg.sitePackages}";
in {
  home.packages = with pkgs; [
    # lua
    lua51Packages.lua
    lua51Packages.luarocks
    # go
    go
    # haskell
    ghc
    haskell-language-server
    ormolu
    cabal-install
    stack
    # nix
    statix
    nixfmt
    nixd
    deadnix
    # web
    nodejs_24
    deno
    typescript # nvim-lspconfig
    htmx-lsp # nvim-lspconfig
    # python
    python-final
    pipenv
    poetry
    uv
    # typst — tinymist/typstyle are not mason-managed (lang-typst.lua sets
    # `mason = false`; mason has no typstyle at all).
    typst
    tinymist
    typstyle
    # latex: latexmk, xelatex, chktex, latexindent, biber for lang-texlive.lua.
    # The top-level scheme already ships biber; adding it separately collides
    # in buildEnv. Downgrade to texliveMedium if closure size bites.
    # Forward-search viewer (zathura) lives in desktop/zathura.nix.
    texliveFull
    # misc
    d2
    # android
    android-tools # adb, fastboot
  ];

  home.sessionPath = ["$HOME/.local/bin"];

  # Read by the neovim config (lang-python.lua); derived from pythonPkg so
  # the python3.x version segment is never hardcoded downstream.
  home.sessionVariables = {
    GLOBAL_PYTHON_FOLDER_PATH = "${python-final}";
    GLOBAL_PYTHON_SITE_PACKAGES = python-site-packages;
  };

  # A global venv so `pip install` outside a project has somewhere to go;
  # created on first shell, activated lazily after that. Test bin/activate, not
  # the dir, and create under flock: sesh restores several tmux panes at once
  # and every zsh raced into `python -m venv`
  # ("[Errno 17] File exists: ~/.venv/include/python3.11", 2026-09-15). On the
  # Entra side ~/.venv is not persisted (home is recreated by himmelblau each
  # boot), so this runs on every first login; losers of the lock skip quietly.
  programs.zsh.initContent = lib.mkOrder 999 ''
    if [ -f "$HOME/.venv/bin/activate" ]; then
      zsh-defer source "$HOME/.venv/bin/activate"
    else
      ( ${pkgs.util-linux}/bin/flock -n 9 && ${python-final}/bin/python -m venv "$HOME/.venv" ) \
        9>"$HOME/.venv.lock" 2>/dev/null
    fi
  '';
}
