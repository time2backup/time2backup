#
# time2backup bash auto-completion handling
#
# This file is part of time2backup (https://time2backup.github.io)
#
# MIT License
# Copyright (c) 2017 Jean Prunneaux
#

# Determine command name and honour $cmd_alias defined in inc/init.sh
_t2b_current_script=$(readlink -f "$0")
_t2b_script_directory=$(dirname "$current_script")
source "$script_directory/init.sh" --gui > /dev/null
_t2b_cmd=$(basename $cmd_alias)

_t2b_complete()
{
    local cur_word prev_word type_list

    # COMP_WORDS is an array of words in the current command line.
    # COMP_CWORD is the index of the current word (the one the cursor is
    # in). So COMP_WORDS[COMP_CWORD] is the current word; we also record
    # the previous word here, although this specific script doesn't
    # use it yet.
    cur_word="${COMP_WORDS[COMP_CWORD]}"
    prev_word="${COMP_WORDS[COMP_CWORD-1]}"

    # Only perform completion if the current word starts with a dash ('-'),
    # meaning that the user is trying to complete an option.
    if [[ ${cur_word} == -* ]] ; then
        # COMPREPLY is the array of possible completions, generated with
        # the compgen builtin.
        COMPREPLY=($(compgen -W '--console --log-level --verbose-level --destination --config --debug --version --help' -- ${cur_word}))
	
    else
        COMPREPLY=( $(compgen -W 'backup restore history explore status stop clean config install uninstall' -- ${cur_word}))
    fi
    return 0
}

# Register _t2b_complete to provide completion for the following commands
complete -F _t2b_complete $_t2b_cmd

# To install :
# sudo ln -s $PWD/inc/t2b_completion.sh /etc/bash_completion.d/
# . /etc/bash_completion.d/tb2-completion.sh

# To remove
# sudo rm /etc/bash_completion.d/t2b_completion.sh
# `complete -W "" time2backup`
