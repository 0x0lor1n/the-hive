# destyle (Qwen3-8B + LoRA) on 127.0.0.1:8080: started on first connect, stopped after `idle`.
{
  lib,
  pkgs,
  config,
  ...
}: let
  # Weights stay in the project tree: a new adapter is a restart, not a rebuild.
  root = "/srv/workspace/projects/llms/destyle";
  base = "${root}/models/Qwen3-8B-Q4_K_M.gguf";
  lora = "${root}/models/destyle-lora-expand-f16.gguf";
  port = 8080;
  inner = 18080;
  idle = "10min";
  llama = pkgs.llama-cpp.override {vulkanSupport = true;};
in {
  systemd.sockets.destyle = {
    description = "destyle rewriter (socket)";
    wantedBy = ["sockets.target"];
    listenStreams = ["127.0.0.1:${toString port}"];
  };

  # llama-server takes no inherited socket, hence the proxy. It exits after `idle`,
  # and StopWhenUnneeded takes the server down with it.
  systemd.services.destyle = {
    description = "destyle rewriter (proxy)";
    requires = ["destyle-server.service"];
    after = ["destyle-server.service"];
    serviceConfig = {
      ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd --exit-idle-time=${idle} 127.0.0.1:${toString inner}";
      DynamicUser = true;
      PrivateTmp = true;
    };
  };

  systemd.services.destyle-server = {
    description = "destyle rewriter (llama-server)";
    stopIfChanged = false;
    unitConfig.StopWhenUnneeded = true;
    path = [pkgs.curl];
    serviceConfig = {
      # No --system-prompt in this llama-cpp; clients send the training prompt.
      ExecStart = lib.concatStringsSep " " [
        "${llama}/bin/llama-server"
        "-m ${base} --lora ${lora}"
        "--host 127.0.0.1 --port ${toString inner}"
        "-ngl 99 -c 4096 --cache-reuse 256"
        "--reasoning-budget 0"
        "--alias destyle-8b-expand"
      ];
      # socket-proxyd does not retry a refused connect: up only once /health answers.
      ExecStartPost = pkgs.writeShellScript "destyle-wait" ''
        for _ in $(seq 120); do
          curl -sf -o /dev/null http://127.0.0.1:${toString inner}/health && exit 0
          sleep 0.5
        done
        exit 1
      '';
      TimeoutStartSec = "90s";
      # Weights via the hive group; admin is the one account sure to be in users.users.
      User = lib.head config.hive.roleHolders.admin;
      SupplementaryGroups = ["video" "render"];
      WorkingDirectory = root;
      Restart = "no";
    };
  };
}
