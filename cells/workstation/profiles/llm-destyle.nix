# destyle: the Qwen3-8B + LoRA rewriter (/srv/workspace/projects/llms/destyle,
# docs/PLAN.md), served on demand on the workstation.
#
# Shape: systemd holds 127.0.0.1:8080; the first connection starts
# llama-server on an inner port and systemd-socket-proxyd shuttles bytes
# across. When the proxy sees no traffic for `idle`, it exits, and the server
# (StopWhenUnneeded, nothing else wants it) goes with it. 5 GB of weights sit
# on the iGPU only while someone is actually rewriting.
#
# Not a container: a container would add a bind mount for /dev/dri and nothing
# else. The service listens on loopback alone and the weights are read-only
# under /srv/workspace, so there is nothing to isolate from.
#
# Not socket-passing to llama-server itself: it does not take an inherited
# fd, hence the proxy. socket-proxyd does not retry a refused connect, so the
# server unit counts as started only once /health answers (ExecStartPost
# loop); the proxy's After= then absorbs the model load (~3 s warm, ~30 s
# from cold disk).
#
# Same binary as the pair generation and the bench (docs/BENCH.md): Vulkan
# llama-cpp, all layers on Iris Xe. Thinking is cut at the server so the
# built-in UI (http://127.0.0.1:8080) needs no per-chat toggle. This
# llama-cpp (0.3.0) has no --system-prompt flag: the training prompt
# (16_train_lora.py) is pasted once into the UI's settings, or sent as the
# system message over /v1/chat/completions.
#
# Adapter and base are read from the project tree, not copied into the
# store: regenerating the adapter (v3, v4, ...) is a restart, not a rebuild.
{
  lib,
  pkgs,
  host,
  ...
}: let
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

  # What the socket activates: the proxy, which pulls the server in.
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
      ExecStart = lib.concatStringsSep " " [
        "${llama}/bin/llama-server"
        "-m ${base} --lora ${lora}"
        "--host 127.0.0.1 --port ${toString inner}"
        "-ngl 99 -c 4096 --cache-reuse 256"
        "--reasoning-budget 0"
        "--alias destyle-8b-expand"
      ];
      # Up means the model is loaded, not that the process exists.
      ExecStartPost = pkgs.writeShellScript "destyle-wait" ''
        for _ in $(seq 120); do
          curl -sf -o /dev/null http://127.0.0.1:${toString inner}/health && exit 0
          sleep 0.5
        done
        exit 1
      '';
      TimeoutStartSec = "90s";
      # Reads the weights through the hive group; /dev/dri is root:video here.
      User = host.userName;
      SupplementaryGroups = ["video" "render"];
      WorkingDirectory = root;
      Restart = "no";
    };
  };
}
