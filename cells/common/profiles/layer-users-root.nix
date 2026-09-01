# Root account and the shared user/group invariants. Universal — every
# installed host gets this, workstation or headless server.
#
# Split out of layer-system.nix in iter 11: that file mixed root (true of
# every host) with the local desktop user (true only of workstations), and
# osgiliath has no local user at all. layer-users-local.nix holds the rest.
{
  globals,
  host,
  ...
}: {
  users.mutableUsers = false;

  users.groups.users.gid = 100;

  # Fleet default from the ENCRYPTED half of globals, with a per-host public
  # override (iter 11.6, completing iteration 10 §1).
  #
  # The override exists for exactly one reason: the playground VMs must keep a
  # DOCUMENTED, PUBLIC passphrase. AGENTS.md quotes it and the justfile's
  # ssh-vm-agent-root recipe types it, so hiding it would break the
  # coding-agent SSH path that exists because the agenix key needs a TPM PIN.
  #
  # Everything else -- dellvis, jarvis, osgiliath -- gets a value that exists
  # only inside secrets/globals.nix.age. That closes the attack chain
  # iteration 10 opened with: boot a stolen laptop, TPM unseals the pool
  # silently by design, log in with a password published in git.
  #
  # No mkDefault: this expression already resolves the per-host case, so a
  # second override layer would just be somewhere else to disagree.
  users.users.root.hashedPassword =
    if host.rootHashedPassword != null
    then host.rootHashedPassword
    else globals.root.hashedPassword;
}
