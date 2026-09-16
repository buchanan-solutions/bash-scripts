#!/usr/bin/env bash
# Lists top N largest Docker container log files in a tab-aligned table,
# numbers them, and optionally truncates selected logs.

show_help() {
    cat <<'EOF'
inspect_docker_logs — list and optionally truncate large Docker container logs

Usage:
  inspect_docker_logs [TOP_N]

Arguments:
  TOP_N   Number of largest logs to show (default: 10)

Examples:
  inspect_docker_logs
  inspect_docker_logs 20
EOF
}

inspect_docker_logs() {
    local top_n=10

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                return 0
                ;;
            -*)
                echo "Unknown option: $1" >&2
                show_help >&2
                return 1
                ;;
            *)
                top_n="$1"
                shift
                break
                ;;
        esac
        shift
    done

    if [[ $# -gt 0 ]]; then
        echo "Unexpected argument(s): $*" >&2
        show_help >&2
        return 1
    fi

    if ! [[ "$top_n" =~ ^[0-9]+$ ]] || [[ "$top_n" -lt 1 ]]; then
        echo "TOP_N must be a positive integer (got: $top_n)" >&2
        return 1
    fi

    echo -e "Scanning top $top_n Docker container logs...\n"

    local -a log_entries=()
    mapfile -t log_entries < <(
        sudo find /var/lib/docker/containers -type f -name '*-json.log' -printf "%s %p\n" \
            | sort -nr \
            | head -n "$top_n"
    )

    if [[ ${#log_entries[@]} -eq 0 ]]; then
        echo "No Docker container log files found under /var/lib/docker/containers."
        return 0
    fi

    printf "%-3s\t%-8s\t%-95s\t%-50s\n" "#" "SIZE" "CONTAINER (IMAGE)" "LOG PATH"
    printf "%-3s\t%-8s\t%-95s\t%-50s\n" "---" "----" "-----------------" "--------"

    declare -A log_map=()
    local i size path hr_size full_cid short_cid info short_path
    for i in "${!log_entries[@]}"; do
        size=$(awk '{print $1}' <<< "${log_entries[$i]}")
        path=$(awk '{print $2}' <<< "${log_entries[$i]}")
        hr_size=$(numfmt --to=iec --suffix=B "$size")

        full_cid=$(basename "$path" | sed 's/-json.log$//')
        short_cid=${full_cid:0:10}

        info=$(docker inspect --format '{{.Name}} ({{.Config.Image}})' "$full_cid" 2>/dev/null || echo "Not found")
        info=$(sed 's|^/||' <<< "$info")

        short_path=$(sed "s/$full_cid/$short_cid.../" <<< "$path")

        printf "%-3s\t%-8s\t%-95s\t%-50s\n" "$((i + 1))" "$hr_size" "$info" "$short_path"
        log_map[$((i + 1))]="$path"
    done

    echo ""
    local user_input
    read -rp "Enter the numbers of logs to truncate (space-separated, or empty to skip): " user_input

    local -a selections=()
    read -r -a selections <<< "$user_input"

    local num log_file
    for num in "${selections[@]}"; do
        [[ -z "$num" ]] && continue
        log_file="${log_map[$num]:-}"
        if [[ -z "$log_file" ]]; then
            echo "Skipping invalid selection: $num"
            continue
        fi

        echo "Truncating log: $log_file"
        sudo truncate -s 0 "$log_file" && echo "Done."
    done
}

main() {
    inspect_docker_logs "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
