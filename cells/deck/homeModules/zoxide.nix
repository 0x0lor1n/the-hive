# zoxide: `z` / `zi` smarter cd.
{
  inputs,
  cell,
}: _: {
  programs.zoxide = {
    enable = true;
    enableBashIntegration = false;
    enableZshIntegration = true;
  };
}
