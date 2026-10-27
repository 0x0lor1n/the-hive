# employer: the M365 tenant's desktop plane. Needs the Entra login
# (profiles/auth-entra.nix) on the same account: Slack and Horizon sign in
# through it, and the https handler is himmelblau's.
{roleInputs, ...}: {
  # Sandboxed (packages.nix); state persists via auth-entra.nix. Horizon
  # sits behind a gm-only sign-in browser (packages.nix).
  home.packages = [
    roleInputs.packages.slack
    roleInputs.packages.horizon-gm
  ];

  # SharePoint/Word/Excel/PowerPoint links open in the o365 app, the rest
  # fall through to Firefox. An account without SSO would get a login wall.
  xdg.mimeApps.defaultApplications."x-scheme-handler/https" = "o365-url-handler.desktop";
}
