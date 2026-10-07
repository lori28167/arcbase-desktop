# Arcbase Desktop — /etc/bash.bashrc (shell interattive)
[[ $- != *i* ]] && return

shopt -s checkwinsize histappend
HISTCONTROL=ignoreboth

if [[ $EUID -eq 0 ]]; then
    PS1='\[\e[1;31m\]\u@\h\[\e[0m\] \[\e[1;34m\]\w\[\e[0m\] # '
else
    PS1='\[\e[1;32m\]\u@\h\[\e[0m\] \[\e[1;34m\]\w\[\e[0m\] \$ '
fi

alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias ll='ls -l'

[[ -r /usr/share/bash-completion/bash_completion ]] && . /usr/share/bash-completion/bash_completion
