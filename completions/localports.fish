# fish completion for localports

complete -c localports -f
complete -c localports -s p -l port -r -d 'Filter by port number'
complete -c localports -l json -d 'Output as JSON'
complete -c localports -s w -l watch -xa '1 2 5 10' -d 'Watch mode (default 2 seconds)'
complete -c localports -s k -l kill -r -d 'Kill process on port'
complete -c localports -s a -l all -d 'With --kill <port>: kill all matching processes'
complete -c localports -l pid -xa '(__fish_complete_pids)' -d 'With --kill <port>: kill only this PID if it is on the port'
complete -c localports -l kill-pid -xa '(__fish_complete_pids)' -d 'Kill a process by explicit PID'
complete -c localports -s f -l force -d 'Skip kill confirmation'
complete -c localports -l verbose -d 'Show owning user and full command'
complete -c localports -l tree -d 'Show each listener parent-process chain'
complete -c localports -l docker -d 'Resolve Docker-owned ports to their container'
complete -c localports -s v -l version -d 'Show version'
complete -c localports -s h -l help -d 'Show help'
complete -c localports -n '__fish_is_first_token' -a version -d 'Show version'
