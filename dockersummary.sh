#!/bin/bash

dockersummary() {
    local compact=0
    local filter=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --compact) compact=1 ;;
            *) filter="$1" ;;
        esac
        shift
    done

    # Collapse docker port lists: drop bind addresses, drop IPv6 duplicates.
    # Emits one unique mapping per line (NUL-safe via newline).
    _compact_port_lines() {
        local ports="$1"
        local seen="|"
        local part compact_part

        IFS=',' read -ra parts <<< "$ports"
        for part in "${parts[@]}"; do
            part="${part#"${part%%[![:space:]]*}"}"
            part="${part%"${part##*[![:space:]]}"}"
            [ -z "$part" ] && continue

            if [[ "$part" =~ ^(\[.+\]|[0-9.]+):([0-9]+-\>.+)$ ]]; then
                compact_part="${BASH_REMATCH[2]}"
            else
                compact_part="$part"
            fi

            case "$seen" in
                *"|${compact_part}|"*) continue ;;
            esac
            seen="${seen}${compact_part}|"
            printf '%s\n' "$compact_part"
        done
    }

    if [ "$compact" -eq 1 ]; then
        local -a names statuses createds
        local -a port_blocks  # each entry: newline-separated port lines
        local name status ports created port_line
        local w_name=4 w_status=6 w_ports=5 w_created=7  # header lengths
        local i first

        while IFS=$'\t' read -r name status ports created; do
            names+=("$name")
            statuses+=("$status")
            createds+=("$created")
            port_blocks+=("$(_compact_port_lines "$ports")")

            (( ${#name} > w_name )) && w_name=${#name}
            (( ${#status} > w_status )) && w_status=${#status}
            (( ${#created} > w_created )) && w_created=${#created}
            while IFS= read -r port_line; do
                [ -z "$port_line" ] && continue
                (( ${#port_line} > w_ports )) && w_ports=${#port_line}
            done <<< "${port_blocks[-1]}"
        done < <(
            docker ps --format '{{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.CreatedAt}}' \
                | if [ -n "$filter" ]; then grep "$filter"; else cat; fi
        )

        printf "%-${w_name}s  %-${w_status}s  %-${w_ports}s  %s\n" \
            "NAME" "STATUS" "PORTS" "CREATED"

        for i in "${!names[@]}"; do
            first=1
            if [ -z "${port_blocks[$i]}" ]; then
                printf "%-${w_name}s  %-${w_status}s  %-${w_ports}s  %s\n" \
                    "${names[$i]}" "${statuses[$i]}" "" "${createds[$i]}"
                continue
            fi
            while IFS= read -r port_line; do
                [ -z "$port_line" ] && continue
                if [ "$first" -eq 1 ]; then
                    printf "%-${w_name}s  %-${w_status}s  %-${w_ports}s  %s\n" \
                        "${names[$i]}" "${statuses[$i]}" "$port_line" "${createds[$i]}"
                    first=0
                else
                    printf "%-${w_name}s  %-${w_status}s  %s\n" \
                        "" "" "$port_line"
                fi
            done <<< "${port_blocks[$i]}"
        done
    elif [ -n "$filter" ]; then
        {
            echo -e "NAME\tSTATUS\tCREATED\tPORTS"
            docker ps --format '{{.Names}}\t{{.Status}}\t{{.CreatedAt}}\t{{.Ports}}' \
                | grep "$filter"
        } | column -t -s $'\t'
    else
        {
            echo -e "NAME\tSTACK\tSTATUS\tCREATED\tPORTS"
            docker ps --format '{{.ID}}\t{{.Names}}\t{{.Status}}\t{{.CreatedAt}}\t{{.Ports}}' \
            | while IFS=$'\t' read -r id name status created ports; do
                stack=$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.project" }}' "$id" 2>/dev/null)
                echo -e "${name}\t${stack:-—}\t${status}\t${created}\t${ports}"
            done
        } | column -t -s $'\t'
    fi
}
