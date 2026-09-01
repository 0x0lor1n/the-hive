{
  globals,
  host,
  ...
}: {
  users.mutableUsers = false;
  users.groups.users.gid = 100;

  # Per-host override (encrypted half) over the fleet default (encrypted half).
  # No mkDefault: the per-host case is resolved here, a second layer would be
  # one more place to disagree.
  users.users.root.hashedPassword =
    if host.rootHashedPassword != null
    then host.rootHashedPassword
    else globals.root.hashedPassword;
}
