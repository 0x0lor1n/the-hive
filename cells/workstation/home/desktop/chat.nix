# Outside nixpak: simplex's AppImage is already bwrap'd (userns in userns),
# mattermost is plain Electron.
{pkgs, ...}: {
  home.packages = [
    pkgs.simplex-chat-desktop
    pkgs.mattermost-desktop
  ];
}
