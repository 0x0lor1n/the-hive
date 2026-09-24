# newt (nmtui, whiptail): its stock scheme is white-on-blue with red
# buttons. NEWT_COLORS takes slang colour names, i.e. the 16 ANSI slots, so
# the actual hexes come from foot's palette (common/theme.nix `ansi`):
# black = bg, blue = crystalBlue, lightgray = oldWhite, gray = fujiGray,
# brown = boatYellow2, white = fujiWhite.
{
  inputs,
  cell,
}: {lib, ...}: let
  sets = {
    root = "white,black";
    roottext = "gray,black";
    helpline = "gray,black";
    window = "white,black";
    border = "blue,black";
    shadow = "black,black";
    title = "blue,black";
    label = "white,black";
    textbox = "white,black";
    acttextbox = "black,blue";
    # Fields need a bg that differs from the window's; with 16 slots that is
    # lightgray.
    entry = "black,lightgray";
    disentry = "gray,black";
    button = "black,gray";
    actbutton = "black,blue";
    compactbutton = "white,black";
    checkbox = "white,black";
    actcheckbox = "black,blue";
    listbox = "white,black";
    actlistbox = "black,blue";
    sellistbox = "black,brown";
    actsellistbox = "black,blue";
    emptyscale = ",gray";
    fullscale = ",blue";
  };
in {
  home.sessionVariables.NEWT_COLORS = lib.concatStringsSep ";" (lib.mapAttrsToList (n: v: "${n}=${v}") sets);
}
