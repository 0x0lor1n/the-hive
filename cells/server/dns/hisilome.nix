# hisilo.me at Njalla as a terranix module. Record values come from globals
# (ipv4/ipv6 of osgiliath), so DNS and the host's interface config cannot
# drift apart. The provider has no "zone" resource: records are imported
# once (`dns import`), then managed here.
{
  host,
  lib,
  ...
}: let
  domain = "hisilo.me";
  # Njalla's ValidTTL: 60 300 900 3600 10800 21600 86400. 300 while the
  # address may still move (v6 arriving); raise after launch.
  ttl = 300;
  bare = cidr: lib.head (lib.splitString "/" cidr);
  v4 = bare host.ipv4.address;
  v6 =
    if host.ipv6 != null
    then bare host.ipv6.address
    else null;
in {
  terraform.required_providers.njalla = {
    source = "Sighery/njalla";
    version = "0.10.0";
  };
  # Path is passed at init by the `dns` wrapper (user state dir, not the repo).
  terraform.backend.local = {};
  # Token from NJALLA_API_TOKEN (the `dns` wrapper decrypts it), never here.
  provider.njalla = {};

  resource.njalla_record_a = {
    apex = {
      inherit domain ttl;
      name = "@";
      content = v4;
    };
    www = {
      inherit domain ttl;
      name = "www";
      content = v4;
    };
  };

  resource.njalla_record_aaaa = lib.mkIf (v6 != null) {
    apex = {
      inherit domain ttl;
      name = "@";
      content = v6;
    };
    www = {
      inherit domain ttl;
      name = "www";
      content = v6;
    };
  };

  # Only Let's Encrypt may issue; the account URI pin can wait until the ACME
  # account is stable.
  resource.njalla_record_caa.le = {
    inherit domain ttl;
    name = "@";
    # The provider takes the RDATA as one string: flags tag "value".
    content = "0 issue \"letsencrypt.org\"";
  };
}
