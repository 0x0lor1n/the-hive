# zoxide: `z` / `zi` smarter cd. Ported 1:1 from jarvis.
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
