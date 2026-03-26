#!/bin/sh

. "$(dirname "$0")/nginx_conf_gen.sh"
. "$(dirname "$0")/sync_project.sh"

if [ -z "$DOMAIN" ]; then
    echo "ERROR: The DOMAIN variable must be defined."
    exit 1
fi

GIT_TOKEN=${GIT_TOKEN:-""}
INTERVAL_SECONDS=${INTERVAL_SECONDS:-120}
CONFIG_FILE=${CONFIG_FILE:-"/projects.json"}

while true; do
    has_run=false
    if [ -f "$CONFIG_FILE" ]; then
        num_projects=$(jq '. | length' "$CONFIG_FILE")
        i=0
        while [ $i -lt "$num_projects" ]; do
            repo_url=$(jq -r ".[$i].REPO_URL" "$CONFIG_FILE")
            base_path=$(jq -r ".[$i].BASE_PATH // \"\"" "$CONFIG_FILE")
            branch_regex=$(jq -r ".[$i].BRANCH_REGEX // \"\"" "$CONFIG_FILE")
            if [ "$repo_url" != "null" ]; then
                [ -z "$base_path" ] && base_path=$(basename "$repo_url" .git)
                sync_project "$repo_url" "$base_path" "$branch_regex" "proj_$i"
                has_run=true
            fi
            i=$((i + 1))
        done
    elif [ -n "$REPO_URL" ]; then
        current_base_path="$BASE_PATH"
        [ -z "$current_base_path" ] && current_base_path=$(basename "$REPO_URL" .git)
        sync_project "$REPO_URL" "$current_base_path" "$BRANCH_REGEX" "default"
        has_run=true
    else
        echo "[$(date +'%H:%M:%S')] No configuration found."
    fi
    if [ "$has_run" = true ]; then
        generate_nginx_conf
    fi
    sleep "$INTERVAL_SECONDS"
done

