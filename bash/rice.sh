# Prompt + colors from my rice. Source it from ~/.bashrc:
#   [ -f ~/.config/bash/rice.sh ] && . ~/.config/bash/rice.sh

# >>> harel-prompt >>>
# harel@arch in ~/path on branch
# ❯                (arrow turns red if the last command failed)
__harel_prompt() {
  local s=$? br=""
  local user='\[\e[1;38;2;74;144;255m\]'   # bold blue
  local dim='\[\e[38;2;110;120;140m\]'     # gray for "in" / "on"
  local path='\[\e[1;38;2;74;144;255m\]'   # bold blue (same as harel@arch)
  local git='\[\e[38;2;170;140;255m\]'     # soft purple
  local ok='\[\e[1;38;2;74;144;255m\]'     # blue arrow
  local bad='\[\e[1;38;2;236;95;103m\]'    # red arrow
  local r='\[\e[0m\]'

  command -v git >/dev/null 2>&1 && br=$(git branch --show-current 2>/dev/null)

  PS1="${user}harel@arch${r} ${dim}in${r} ${path}\w${r}"
  [ -n "$br" ] && PS1+=" ${dim}on${r} ${git}${br}${r}"
  PS1+="\n"
  if [ $s -eq 0 ]; then PS1+="${ok}❯${r} "; else PS1+="${bad}❯${r} "; fi
}
PROMPT_COMMAND=__harel_prompt
# <<< harel-prompt <<<

# >>> harel-colors >>>
alias sudo='sudo '                       # lets the aliases below work after sudo too
alias grep='grep --color=auto'
alias diff='diff --color=auto'
alias ip='ip -color=auto'
export LESS='-R'

# ls -> eza
if command -v eza >/dev/null 2>&1; then
  alias ls='eza --group-directories-first'
  alias ll='eza -la --git --header --group-directories-first'
  alias la='eza -a --group-directories-first'
  alias tree='eza --tree'
else
  alias ls='ls --color=auto --group-directories-first'
  alias ll='ls -lah --color=auto'
fi

# cat and man pages -> bat   (\cat still gives you the plain cat)
if command -v bat >/dev/null 2>&1; then
  alias cat='bat --paging=never --style=plain'
  export MANPAGER="sh -c 'col -bx | bat -l man -p'"
  export MANROFFOPT='-c'
fi

# Network and system tools -> grc
if command -v grc >/dev/null 2>&1; then
  for __c in nmap ping traceroute dig whois netstat ss ps df du free mount lsblk id uptime lsof ifconfig make gcc \
             tcpdump iptables lspci lsmod blkid findmnt stat sysctl last vmstat sensors getfacl; do
    alias "$__c=grc --colour=auto $__c"
  done
  unset __c
fi

# John the Ripper: cracked passwords green, users yellow, errors red
if command -v john >/dev/null 2>&1; then
  john() {
    # plain output when piped or when printing candidates/lists
    if [ ! -t 1 ]; then command john "$@"; return; fi
    case " $* " in *" --stdout"*|*" --list="*) command john "$@"; return ;; esac
    local G=$'\e[1;32m' Y=$'\e[1;33m' R=$'\e[1;31m' C=$'\e[1;36m' M=$'\e[35m' D=$'\e[90m' N=$'\e[0m'
    stdbuf -oL -eL john "$@" 2>&1 | ( trap '' INT; exec sed -u -E \
      -e "s/^(Warning:.*)$/${Y}\1${N}/;t" \
      -e "s/^((Error|No password hashes|Unknown|Invalid|Can't|fopen:).*)$/${R}\1${N}/;t" \
      -e "s/^(Loaded [0-9]+ password hash(es)?)(.*\()([^ ()]+)(.*)$/${C}\1${N}\3${M}\4${N}\5/;t" \
      -e "s/^(Session completed.*)$/${G}\1${N}/;t" \
      -e "s/^(Session (aborted|stopped).*)$/${R}\1${N}/;t" \
      -e "s/^([0-9]+ password hash(es)? cracked), ([0-9]+ left)$/${G}\1${N}, ${Y}\3${N}/;t" \
      -e "s/^([0-9]+g) ([0-9]+:[0-9:]+) DONE(.*)$/${G}\1${N} ${D}\2${N} ${G}DONE${N}\3/;t" \
      -e "s/^([0-9]+g) ([0-9]+:[0-9:]+)(.*)$/${G}\1${N} ${D}\2${N}\3/;t" \
      -e "s/^((Using default|Will run|Press 'q'|Proceeding with|Note:|Cost [0-9]|Node numbers|Use the |Almost done|Warning).*)$/${D}\1${N}/;t" \
      -e "s/^(.*[^ ])( +)\(([^()]*)\)$/${G}\1${N}\2(${Y}\3${N})/;t" \
      -e "s/^([^: ]+):([^:]*)(:.*)?$/${Y}\1${N}:${G}\2${N}\3/;t" )
    return "${PIPESTATUS[0]}"
  }
fi
# Colored compiler errors; bat uses the terminal's (Ghostty's) palette
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'
export BAT_THEME='ansi'
# <<< harel-colors <<<

# Shortcuts
alias ff='fastfetch'
alias c='clear'
alias e='exit'
alias reload='. ~/.bashrc'

# Prefer Starship? Uncomment to use config/starship.toml instead of the prompt above:
# command -v starship >/dev/null && eval "$(starship init bash)"
