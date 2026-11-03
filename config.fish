source /usr/share/cachyos-fish-config/cachyos-config.fish

# overwrite greeting
# potentially disabling fastfetch
#function fish_greeting
#    # smth smth
#end

set -U fish_greeting
starship init fish | source
zoxide init fish | source

alias cat='bat'
alias ll='eza -la --icons --git'
alias tree='eza --tree --icons'
starship init fish | source
starship init fish | source
