# bat: `cat` with syntax highlighting, plus `help <cmd>` piping --help
# through bat's help language.
{
  inputs,
  cell,
}: {
  lib,
  pkgs,
  ...
}: let
  c = inputs.cells.common.theme.colors;

  # Upstream's own tmTheme: bg/fg/selection are already common/theme.nix's
  # bg/fg/selection, so it is taken as is rather than regenerated. delta
  # reads it too, through bat's cache (git.nix syntax-theme).
  kanagawaSrc = pkgs.fetchFromGitHub {
    owner = "rebelot";
    repo = "kanagawa.nvim";
    rev = "bb85e4bfc8d89b0e62c8fa53ccdd13d12e2f77b3";
    hash = "sha256-fMP4NUCKD1ZcNkaHy6SuNm020ECXpBOihGv2n1wyTN4=";
  };

  # Upstream has no markup.* rules beyond diff, so Markdown came out as
  # plain fg. Colours follow kanagawa.nvim wave's treesitter @markup links.
  markupRule = scope: settings: ''
    <dict>
      <key>scope</key>
      <string>${scope}</string>
      <key>settings</key>
      <dict>
    ${lib.concatStrings (lib.mapAttrsToList (k: v: "    <key>${k}</key><string>${v}</string>\n") settings)}  </dict>
    </dict>
  '';
  markupRules = lib.concatStrings [
    (markupRule "markup.heading, punctuation.definition.heading" {foreground = "#${c.crystalBlue}";})
    (markupRule "markup.bold" {fontStyle = "bold";})
    (markupRule "markup.italic" {fontStyle = "italic";})
    (markupRule "markup.raw" {foreground = "#${c.springGreen}";})
    (markupRule "markup.underline.link" {
      foreground = "#${c.springBlue}";
      fontStyle = "underline";
    })
    (markupRule "markup.quote" {foreground = "#${c.oniViolet2}";})
    (markupRule "punctuation.definition.list_item, markup.list.numbered.bullet" {foreground = "#${c.springViolet1}";})
  ];
  kanagawaTheme = pkgs.runCommand "kanagawa-tmtheme" {inherit markupRules;} ''
    mkdir $out
    substitute ${kanagawaSrc}/extras/tmTheme/kanagawa.tmTheme $out/kanagawa.tmTheme \
      --replace-fail '    </array>' "$markupRules    </array>"
  '';
in {
  programs.bat = {
    enable = true;
    themes.kanagawa = {
      src = kanagawaTheme;
      file = "kanagawa.tmTheme";
    };
    config.theme = "kanagawa";
  };

  home.shellAliases.cat = "bat --plain";

  programs.zsh.initContent = lib.mkOrder 1000 ''
    # Call batman
    function help() {
      "$@" --help 2>&1 | bat --plain --language=help
    }
  '';
}
