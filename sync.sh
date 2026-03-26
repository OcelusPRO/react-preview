#!/bin/sh

if [ -z "$DOMAIN" ]; then
    echo "ERREUR : La variable DOMAIN doit être définie."
    exit 1
fi

INTERVAL_SECONDS=${INTERVAL_SECONDS:-120}
CONFIG_FILE=${CONFIG_FILE:-"/projects.json"}

generate_nginx_conf() {
    local conf_file="/etc/nginx/http.d/default.conf"
    local tmp_conf="/tmp/default.conf.tmp"

    echo "server {" > "$tmp_conf"
    echo "    listen 80;" >> "$tmp_conf"
    echo "    root /var/www/html;" >> "$tmp_conf"
    echo "    index index.html;" >> "$tmp_conf"

    find /var/www/html -type f -name "index.html" | awk '{ print length, $0 }' | sort -rn | cut -d" " -f2- | while read -r index_path; do
        local dir_path=$(dirname "$index_path")
        local location_path=$(echo "$dir_path" | sed 's|^/var/www/html||')

        if [ -z "$location_path" ]; then
            location_path="/"
        fi

        local loc_route="$location_path"
        if [ "$loc_route" != "/" ]; then
            loc_route="$loc_route/"
        fi

        echo "    location $loc_route {" >> "$tmp_conf"
        echo "        try_files \$uri \$uri/ $location_path/index.html;" >> "$tmp_conf"
        echo "    }" >> "$tmp_conf"
    done

    echo "}" >> "$tmp_conf"

    if ! cmp -s "$tmp_conf" "$conf_file"; then
        mv "$tmp_conf" "$conf_file"
        nginx -s reload 2>/dev/null || true
        echo "⚙️ Configuration Nginx rechargée dynamiquement."
    fi
}

generate_index() {
    local dest_dir="$1"
    local bp_clean="$2"
    local base_path="$3"
    local json_file="$dest_dir/branches.json"
    local index_file="$dest_dir/index.html"

    # Copier le fichier HTML statique depuis le template embarqué dans l'image
    cp /template.html "$index_file"

    # Construire le fichier JSON
    echo "{" > "$json_file"
    echo "  \"base_path\": \"$base_path\"," >> "$json_file"
    echo "  \"last_update\": \"$(date +'%d/%m/%Y %H:%M:%S')\"," >> "$json_file"
    echo "  \"branches\": [" >> "$json_file"

    first=true
    for hash_file in $(ls "$dest_dir"/*.hash 2>/dev/null); do
        safe_branch=$(basename "$hash_file" .hash)
        if [ -d "$dest_dir/$safe_branch" ]; then
            if [ "$bp_clean" = "/" ]; then
                link="/$safe_branch/"
            else
                link="$bp_clean/$safe_branch/"
            fi

            if [ "$first" = true ]; then
                first=false
            else
                echo "    ," >> "$json_file"
            fi
            echo "    { \"name\": \"$safe_branch\", \"link\": \"$link\" }" >> "$json_file"
        fi
    done

    # Nouvelle ligne pour terminer proprement le tableau JSON
    echo "" >> "$json_file"
    echo "  ]" >> "$json_file"
    echo "}" >> "$json_file"
}

sync_project() {
    local repo_url="$1"
    local base_path="$2"
    local branch_regex="$3"
    local project_id="$4"

    local bp_clean="/$(echo "$base_path" | sed 's/^\///' | sed 's/\/$//')"
    bp_clean=$(echo "$bp_clean" | sed 's/\/\//\//g')
    if [ "$bp_clean" != "/" ]; then
        bp_clean=$(echo "$bp_clean" | sed 's/\/$//')
    fi

    local dest_dir="/var/www/html$bp_clean"
    local work_dir="/tmp/workdir/$project_id"

    mkdir -p "$dest_dir"
    mkdir -p "$work_dir"
    cd "$work_dir" || return

    if [ ! -d ".git" ]; then
        echo "[$base_path] Clone initial du dépôt depuis $repo_url..."
        git clone "$repo_url" .
    fi

    echo "[$base_path] [$(date +'%H:%M:%S')] Vérification des mises à jour..."
    git fetch --all --prune --quiet

    active_safe_branches=""

    for branch in $(git branch -r | grep origin/ | grep -v HEAD | sed 's/origin\///'); do
        if [ -n "$branch_regex" ]; then
            if ! echo "$branch" | grep -Eq "$branch_regex"; then continue; fi
        fi

        safe_branch=$(echo "$branch" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9]/-/g' -e 's/^-//' -e 's/-$//')
        active_safe_branches="$active_safe_branches $safe_branch"

        remote_hash=$(git rev-parse "origin/$branch")
        hash_file="$dest_dir/$safe_branch.hash"
        current_hash=""
        if [ -f "$hash_file" ]; then current_hash=$(cat "$hash_file"); fi

        if [ "$remote_hash" != "$current_hash" ]; then
            echo "[$base_path] Nouvelle version détectée sur la branche '$branch' ($remote_hash)."

            git clean -fdx
            git checkout -B "$branch" "origin/$branch" --quiet

            if [ -f "package.json" ]; then
                if [ -f "package-lock.json" ]; then
                    npm ci --silent
                else
                    npm install --silent
                fi

                if [ "$bp_clean" = "/" ]; then
                    full_base_path="/$safe_branch/"
                else
                    full_base_path="$bp_clean/$safe_branch/"
                fi

                echo "[$base_path] Build de la branche '$branch' avec BASE=$full_base_path..."

                VITE_BASE_PATH="$full_base_path" npm run build -- --base="$full_base_path" || { echo "Build échoué"; continue; }

                rm -rf "$dest_dir/$safe_branch"
                mkdir -p "$dest_dir/$safe_branch"
                cp -r dist/* "$dest_dir/$safe_branch/" 2>/dev/null || true
                echo "$remote_hash" > "$hash_file"
                echo "[$base_path] Branche déployée sur https://$DOMAIN$full_base_path"
            fi
        fi
    done

    for dir in $(find "$dest_dir" -mindepth 1 -maxdepth 1 -type d); do
        dir_name=$(basename "$dir")
        is_active=false
        for active_branch in $active_safe_branches; do
            if [ "$dir_name" = "$active_branch" ]; then is_active=true; break; fi
        done

        if [ "$is_active" = false ] && [ "$dir_name" != "index.html" ] && [ "$dir_name" != "branches.json" ]; then
            echo "[$base_path] Nettoyage de la branche supprimée : '$dir_name'..."
            rm -rf "$dir"
            rm -f "$dest_dir/$dir_name.hash"
        fi
    done

    generate_index "$dest_dir" "$bp_clean" "$base_path"
}

while true; do
    has_run=false
    if [ -f "$CONFIG_FILE" ]; then
        num_projects=$(jq '. | length' "$CONFIG_FILE")
        i=0
        while [ $i -lt "$num_projects" ]; do
            repo_url=$(jq -r ".[$i].REPO_URL" "$CONFIG_FILE")
            base_path=$(jq -r ".[$i].BASE_PATH" "$CONFIG_FILE")
            branch_regex=$(jq -r ".[$i].BRANCH_REGEX // \"\"" "$CONFIG_FILE")

            if [ "$repo_url" != "null" ] && [ "$base_path" != "null" ]; then
                sync_project "$repo_url" "$base_path" "$branch_regex" "proj_$i"
                has_run=true
            fi
            i=$((i + 1))
        done
    elif [ -n "$REPO_URL" ] && [ -n "$BASE_PATH" ]; then
        sync_project "$REPO_URL" "$BASE_PATH" "$BRANCH_REGEX" "default"
        has_run=true
    else
        echo "[$(date +'%H:%M:%S')] Aucune configuration trouvée."
    fi

    if [ "$has_run" = true ]; then
        generate_nginx_conf
    fi

    sleep "$INTERVAL_SECONDS"
done