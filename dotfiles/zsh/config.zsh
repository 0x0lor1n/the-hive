# Completion
# ----------
# https://zsh.sourceforge.io/Doc/Release/Completion-System.html
# https://github.com/Phantas0s/.dotfiles/blob/master/zsh/completion.zsh
# https://thevaluable.dev/zsh-completion-guide-examples/
# https://stackoverflow.com/questions/23152157/how-does-the-zsh-list-colors-syntax-work/23568183#23568183
# https://github.com/backdround/configuration/blob/046d9490dda15998cc2223de44e45cbcb09ef7b5/configs/terminal/zsh/zshrc#L42
zstyle ':completion:*' remote-access no
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS} 'ma=48;5;2;38;5;16;1'
zstyle ':completion:*:*' list-colors '=(#b)*(-- *)==38;5;8'
zstyle ':completion:*:functions' list-colors '=*=38;5;4'
zstyle ':completion:*:commands' list-colors '=(#b)*(-- *)==38;5;8' '=^([a-zA-Z])$='
zstyle ':completion:*:aliases' list-colors '=*=38;5;4'
zstyle ':completion:*:options' list-colors '=(#b)*(-- *)=38;5;14=38;5;8' '=^(-- *)=38;5;14'
zstyle ':completion:*:parameters' list-colors '=(#b)*(-- *)=38;5;216=38;5;8' '=^(-- *)=38;5;216'
zstyle ':completion:*:unambiguous' format $'%{\e[38;5;8m%}-- common substring: %{\e[38;5;2m%}%d %{\e[38;5;8m%}--%{\e[0m%}'
zstyle ':completion:*:descriptions' format $'%{\e[38;5;8m%}-- %d --%{\e[0m%}'
zstyle ':completion:*:messages' format $'%{\e[38;5;8m%}-- %d --%{\e[0m%}'
zstyle -e ':completion:*:warnings' format autocomplete:config:format:warnings
autocomplete:config:format:warnings() {
  [[ $CURRENT == 1 && -z $PREFIX$SUFFIX ]] ||
      typeset -ga reply=( $'%{\e[38;5;1m%}'"-- no matching %d completions --"$'%{\e[0m%}' )
      }

# Misc
# ----
# https://github.com/marlonrichert/zsh-launchpad/blob/main/.config/zsh/rc.d/07-opts.zsh
setopt INTERACTIVE_COMMENTS
setopt HASH_EXECUTABLES_ONLY
setopt NUMERIC_GLOB_SORT

# Leave out expansion
zstyle ':completion:*' completer _complete _complete:-fuzzy _correct _approximate _ignored

# History
# -------
# https://hassek.github.io/zsh-history-tweaking/
setopt HIST_REDUCE_BLANKS
setopt HIST_FIND_NO_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_SAVE_NO_DUPS
setopt APPEND_HISTORY

# Ignore certain commands in history
# TODO: put git settings into separate git.nix otherwise aliases are not skipped here (Ex: git s)
HISTORY_IGNORE_REGEX='^(rm .*|rmd .*|git s|git unstash|git stash.*)$'
function zshaddhistory() {
  emulate -L zsh
  [[ ! $1 =~ "$HISTORY_IGNORE_REGEX" ]]
}
