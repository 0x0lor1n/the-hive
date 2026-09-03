# The one theme for the whole repo, as data. Read as
# `inputs.cells.theme.palettes.kanagawa` from any cell; everything that
# paints a pixel (foot, fuzzel, mako, swaylock, swaybg, dwl, somebar, the VT
# console + tuigreet) derives its colours from here so a hex change is one
# edit. Hexes are rrggbb without '#': each consumer adds its own prefix/alpha.
{...}: {
  kanagawa = rec {
    # Kanagawa Wave, verbatim from rebelot/kanagawa.nvim.
    colors = {
      # backgrounds
      sumiInk0 = "16161d";
      sumiInk1 = "181820";
      sumiInk3 = "1f1f28"; # default bg
      sumiInk4 = "2a2a37"; # lighter bg (statusline, popups)
      sumiInk5 = "363646"; # cursorline
      sumiInk6 = "54546d"; # comments, inactive borders
      # foregrounds
      fujiWhite = "dcd7ba"; # default fg
      oldWhite = "c8c093";
      fujiGray = "727169";
      # accents
      crystalBlue = "7e9cd8";
      springViolet1 = "938aa9";
      oniViolet = "957fb8";
      autumnRed = "c34043";
      samuraiRed = "e82424";
      autumnGreen = "76946a";
      springGreen = "98bb6c";
      boatYellow2 = "c0a36e";
      carpYellow = "e6c384";
      waveAqua1 = "6a9589";
      waveAqua2 = "7aa89f";
      waveBlue1 = "223249";
      waveBlue2 = "2d4f67";
      surimiOrange = "ffa066";
      peachRed = "ff5d62";
      sakuraPink = "d27e99";
      springBlue = "7fb4ca";
      lightBlue = "a3d4d5";
      waveRed = "e46876";
      roninYellow = "ff9e3b";
      dragonBlue = "658594";
    };

    # Semantic roles, mirroring hisilome's style.css so the desktop and the
    # site agree on what "link"/"accent"/"border" mean.
    roles = with colors; {
      bg = sumiInk3;
      bgDim = sumiInk0;
      bgAlt = sumiInk4;
      fg = fujiWhite;
      muted = fujiGray;
      border = sumiInk5;
      focus = crystalBlue; # link on the site, focused border in dwl
      hover = oniViolet;
      accent = springGreen;
      highlight = carpYellow;
      urgent = autumnRed;
      selection = waveBlue2;
    };

    # The 16 ANSI slots: black red green yellow blue magenta cyan white, then
    # bright. Terminal (foot) and the kernel VT (console.colors) share this.
    ansi = with colors; [
      sumiInk3 autumnRed autumnGreen boatYellow2 crystalBlue oniViolet waveAqua1 oldWhite
      fujiGray samuraiRed springGreen carpYellow springBlue springViolet1 waveAqua2 fujiWhite
    ];
  };
}
