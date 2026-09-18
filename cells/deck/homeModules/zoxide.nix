# zoxide: `z` / `zi` smarter cd.
{
  inputs,
  cell,
}: {...}: {
  programs.zoxide = {
    enable = true;
    enableBashIntegration = false;
    enableZshIntegration = true;
  };
}
