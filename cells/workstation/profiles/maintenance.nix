# Bounded generations: the current one plus two to roll back to. Also frees
# the ESP, where each lanzaboote UKI is a full kernel + initrd.
{config, ...}: let
  keep = 3;
in {
  # lanzaboote defaults its own configurationLimit to this value, so one
  # option covers both loaders. 0 would mean unlimited.
  boot.loader.systemd-boot.configurationLimit = keep;

  # nh keeps a *count*, which is what "max 3" means; nix.gc only knows age.
  # `clean all` also runs the store GC. --keep-since 1d spares a generation
  # switched to today even when it is the fourth.
  programs.nh = {
    enable = true;
    clean = {
      enable = true;
      dates = "weekly";
      extraArgs = "--keep ${toString keep} --keep-since 1d";
    };
  };

  assertions = [
    {
      assertion = config.boot.loader.systemd-boot.configurationLimit == keep;
      message = "maintenance: something overrides systemd-boot.configurationLimit; lanzaboote follows it.";
    }
  ];
}
