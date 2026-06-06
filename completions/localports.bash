# bash completion for localports

_localports()
{
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    opts="--port -p --json --watch -w --kill -k --all -a --pid --kill-pid --force -f --verbose --tree --docker --version -v --help -h version"

    case "${prev}" in
        --port|-p|--kill|-k)
            # Port number expected.
            return 0
            ;;
        --watch|-w)
            # Optional refresh interval expected.
            COMPREPLY=( $(compgen -W "1 2 5 10" -- "${cur}") )
            return 0
            ;;
        --pid|--kill-pid)
            # PID expected.
            COMPREPLY=( $(compgen -W "$(ps -axo pid= 2>/dev/null)" -- "${cur}") )
            return 0
            ;;
    esac

    if [[ "${cur}" == -* ]]; then
        COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
        return 0
    fi

    if [[ ${COMP_CWORD} -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "version" -- "${cur}") )
    fi
}

complete -F _localports localports
