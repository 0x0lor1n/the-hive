# Palette artefacts for chat apps whose theme is not a file Nix can own: each
# is imported once by hand and then lives in the app (or on the server).
# Redo after a palette change. Paths in ~/.config/chat-themes/:
# - slack.txt: Preferences → Appearance → Custom theme → Import theme →
#   "Paste your legacy theme colors" (8 hexes: column bg, menu hover, active
#   item, active text, hover item, text, presence, mention badge). Per workspace.
# - mattermost.json: Settings → Display → Theme → Custom → Copy/paste theme.
#   Per server account; the desktop app follows it (themeSyncing).
# - kanagawa.tdesktop-theme: copy to ~/Downloads (the only dir the nixpak
#   Telegram sees), open it from Saved Messages or drag it into a chat, Apply.
{
  lib,
  pkgs,
  theme,
  ...
}: let
  r = theme.roles;
  c = theme.colors;
  h = x: "#${x}";

  slack = lib.concatMapStringsSep "," h [r.bgDim r.bgAlt r.selection r.fg r.bgAlt r.fg r.success r.urgent];

  mattermost =
    lib.mapAttrs (_: h) {
      sidebarBg = r.bgDim;
      sidebarText = r.fg;
      sidebarUnreadText = r.fg;
      sidebarTextHoverBg = r.bgAlt;
      sidebarTextActiveBorder = r.focus;
      sidebarTextActiveColor = r.fg;
      sidebarHeaderBg = c.sumiInk1;
      sidebarHeaderTextColor = r.fg;
      sidebarTeamBarBg = r.bgDim;
      onlineIndicator = r.success;
      awayIndicator = r.warning;
      dndIndicator = r.urgent;
      mentionBg = r.focus;
      mentionBj = r.focus;
      mentionColor = r.bgDim;
      centerChannelBg = r.bg;
      centerChannelColor = r.fg;
      newMessageSeparator = r.info;
      linkColor = r.focus;
      buttonBg = r.focus;
      buttonColor = r.bgDim;
      errorTextColor = c.waveRed;
      mentionHighlightBg = r.selection;
      mentionHighlightLink = r.info;
    }
    // {codeTheme = "monokai";};

  # Keys the nearest-colour snap gets wrong (all light-on-blue night roles
  # would land on the same blues): surfaces, selection, text on accents.
  telegramPins = {
    windowBg = r.bg;
    windowFg = r.fg;
    windowBgOver = r.bgAlt;
    windowBgRipple = r.border;
    windowSubTextFg = r.muted;
    windowBoldFg = r.fg;
    windowBgActive = r.focus;
    windowFgActive = r.fg;
    windowActiveTextFg = r.focus;
    activeButtonBg = r.focus;
    activeButtonBgOver = r.info;
    activeButtonFg = r.bgDim;
    activeButtonFgOver = r.bgDim;
    lightButtonFg = r.focus;
    menuBg = r.bgAlt;
    menuBgOver = r.border;
    boxBg = r.bgAlt;
    titleBg = r.bgDim;
    titleBgActive = r.bgDim;
    dialogsBgActive = r.selection;
    dialogsUnreadBg = r.focus;
    dialogsUnreadFg = r.bgDim;
    dialogsUnreadBgMuted = r.border;
    sideBarBg = r.bgDim;
    sideBarBgActive = r.bgAlt;
    sideBarTextFgActive = r.focus;
    sideBarIconFgActive = r.focus;
    historyComposeAreaBg = r.bgAlt;
    historyPinnedBg = r.bgAlt;
    msgInBg = r.bgAlt;
    msgOutBg = r.selection;
    msgInBgSelected = c.waveBlue1;
    msgOutBgSelected = c.waveBlue1;
    historyTextOutFg = r.fg;
    historyLinkInFg = r.info;
    historyLinkOutFg = r.info;
    boxTextFgGood = r.success;
    boxTextFgError = r.urgent;
  };

  tg = pkgs.telegram-desktop.unwrapped;
  telegram =
    pkgs.runCommand "kanagawa.tdesktop-theme" {
      colors = builtins.toJSON c;
      pins = builtins.toJSON telegramPins;
      passAsFile = ["colors" "pins"];
    } ''
      ${lib.getExe pkgs.python3} ${./__telegram-theme.py} \
        ${tg.src}/Telegram/lib_ui/ui/colors.palette \
        ${tg.src}/Telegram/Resources/night.tdesktop-theme \
        "$colorsPath" "$pinsPath" $out
    '';
in {
  xdg.configFile = {
    "chat-themes/slack.txt".text = slack + "\n";
    "chat-themes/mattermost.json".source = (pkgs.formats.json {}).generate "mattermost-kanagawa.json" mattermost;
    "chat-themes/kanagawa.tdesktop-theme".source = telegram;
  };
}
