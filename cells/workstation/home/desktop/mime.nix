# Default browser for the OpenURI portal: sandboxed apps (Slack SSO
# redirect) hand links to xdg-desktop-portal, which resolves the
# x-scheme-handler default via GAppInfo and, with one set, launches it
# without an app-chooser dialog. Firefox is a systemPackage
# (browser-firefox.nix), so its .desktop is on XDG_DATA_DIRS for both users.
# Desktop-only: without a compositor there is no portal to ask.
{lib, ...}: {
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/http" = "firefox.desktop";
      # mkDefault: the type is a list and would merge with a role's
      # override (roles/employer.nix) instead of yielding to it.
      "x-scheme-handler/https" = lib.mkDefault "firefox.desktop";
      "text/html" = "firefox.desktop";
      # slack.com hands the SSO token to the app through a slack:// link that
      # must route to the (sandboxed) Slack entry, not the browser.
      "x-scheme-handler/slack" = "slack.desktop";
    };
  };
}
