# Key codes (application mode - powerlevel10k)
key_up="^[OA"
key_down="^[OB"
key_left="^[OD"
key_right="^[OC"

# Vi insert mode bindings
bindkey -M viins '^R' histdb-skim-widget
bindkey -M viins '^y' copybuffer  # Copy current command line to clipboard

# Autosuggestions: RightArrow accepts at end of line, moves cursor otherwise
_autosuggest_forward_char() {
  if (( CURSOR == ${#BUFFER} )) && [[ -n "$POSTDISPLAY" ]]; then
    zle autosuggest-accept
  else
    zle .forward-char
  fi
}
zle -N _autosuggest_forward_char
bindkey -M viins '^[OC' _autosuggest_forward_char   # RightArrow (application mode - p10k)
bindkey -M viins '^[[C' _autosuggest_forward_char   # RightArrow (normal mode - fallback)

# ================
# Completion menu
# ================

# [Tab] - enter menu (menu-select from zsh-autocomplete)
# Override fzf-completion binding
bindkey '\t' menu-select              # main keymap
bindkey -M viins '\t' menu-select     # vi insert mode
bindkey -M emacs '\t' menu-select     # emacs mode (fallback)
bindkey -M menuselect '\t' menu-complete

# [Shift+Tab] - reverse
bindkey '^[[Z' menu-select
bindkey -M viins '^[[Z' menu-select
bindkey -M menuselect '^[[Z' reverse-menu-complete

# [Arrow keys] - navigate in menu
bindkey -M menuselect "$key_up" up-line-or-history
bindkey -M menuselect "$key_down" down-line-or-history
bindkey -M menuselect "$key_left" backward-char
bindkey -M menuselect "$key_right" forward-char

# Skim widgets (fuzzy search) - provided by skim zsh integration
# [Alt+C] - fuzzy cd into directory
# [Ctrl+T] - fuzzy file search
# Note: These are automatically bound by skim's key-bindings.zsh

# [Ctrl+y] - accept and exit selected option
bindkey -M menuselect '^Y' accept-line

# [Ctrl+e] - undo and exit completion menu
bindkey -M menuselect '^E' undo

# [Esc] - abort completion
bindkey -M menuselect '^[' send-break

# [Enter] - execute command (not just accept completion)
bindkey -M menuselect '\r' .accept-line

# [Backspace] - exit menu / undo
bindkey -M menuselect '^?' undo

# [Ctrl+\] - search in the completion menu
bindkey -M viins '^\' menu-search
