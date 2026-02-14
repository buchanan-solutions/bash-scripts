#!/bin/bash

dockersummary() {
    local filter="$1"

    if [ -n "$filter" ]; then
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