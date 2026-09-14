# Real which
function rich() {
  realpath $(which -- "$@")
}

# Copy current command line to clipboard
function copybuffer() {
  printf "%s" "$BUFFER" | clipcopy
}
zle -N copybuffer

# Kill process on specified port
function killport() {
  local pids=$(lsof -t -i:"$1" 2>/dev/null)
  if [[ -z "$pids" ]]; then
    echo "No process found on port $1"
    return 1
  fi
  echo "Killing PIDs: $pids"
  kill -9 $pids 2>/dev/null || sudo kill -9 $pids
}

# Toggle OpenCode agent models safely
function oc-swap() {
  if [[ $# -ne 2 ]]; then
    echo "Usage: oc-swap <agent> <preset>"
    echo ""
    echo "Available agents:"
    echo "  atlas     - Atlas agent (kimi, sonnet)"
    echo "  librarian - Librarian agent (glm, gemini)"
    return 1
  fi

  local agent="$1"
  local preset="$2"
  local model_id=""
  local friendly_name=""
  # oh-my-opencode.json lives with the dotfiles (edited in place, like this file)
  local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/oh-my-opencode.json"

  case "$agent" in
    atlas)
      case "$preset" in
        kimi)
          model_id="nvidia/moonshotai/kimi-k2.5"
          friendly_name="NVIDIA Kimi K2.5"
          ;;
        sonnet)
          model_id="anthropic/claude-sonnet-4-5"
          friendly_name="Claude Sonnet"
          ;;
        *)
          echo "Error: Unknown preset '$preset' for atlas"
          echo "Available presets: kimi, sonnet"
          return 1
          ;;
      esac
      ;;
    librarian)
      case "$preset" in
        glm)
          model_id="nvidia/z-ai/glm4.7"
          friendly_name="Z-AI GLM 4.7"
          ;;
        gemini)
          model_id="google/gemini-3-flash-preview"
          friendly_name="Gemini 3 Flash"
          ;;
        *)
          echo "Error: Unknown preset '$preset' for librarian"
          echo "Available presets: glm, gemini"
          return 1
          ;;
      esac
      ;;
    *)
      echo "Error: Unknown agent '$agent'"
      echo "Available agents: atlas, librarian"
      return 1
      ;;
  esac

  local temp_file=$(mktemp)
  if ! jq --arg model "$model_id" ".agents[\"$agent\"].model = \$model" "$config_file" > "$temp_file"; then
    echo "Error: Failed to update JSON"
    rm -f "$temp_file"
    return 1
  fi

  mv "$temp_file" "$config_file"
  
  local agent_display="${(C)agent}"
  echo "$agent_display → $friendly_name"
}
