#!/bin/sh

if [ -z "$DOMAIN" ]; then
    echo "ERREUR : La variable DOMAIN doit être définie."
    exit 1
fi

INTERVAL_SECONDS=${INTERVAL_SECONDS:-120}
CONFIG_FILE=${CONFIG_FILE:-"/projects.json"}

generate_index() {
    local dest_dir="$1"
    local bp_clean="$2"
    local base_path="$3"
    local index_file="$dest_dir/index.html"

    echo "<!DOCTYPE html>" > "$index_file"
    echo "<html lang=\"fr\"><head><meta charset=\"UTF-8\"><title>Previews for $base_path</title>" >> "$index_file"
    echo "<style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; line-height: 1.6; color: #333; max-width: 800px; margin: 0 auto; padding: 40px 20px; background-color: #f4f7f9; }
        h1 { color: #2c3e50; border-bottom: 2px solid #3498db; padding-bottom: 10px; }
        ul { list-style: none; padding: 0; }
        li { background: white; margin: 10px 0; padding: 15px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); transition: transform 0.2s; }
        li:hover { transform: translateY(-2px); box-shadow: 0 4px 8px rgba(0,0,0,0.15); }
        a { text-decoration: none; color: #3498db; font-weight: bold; display: block; }
        .update-time { font-size: 0.8em; color: #7f8c8d; margin-top: 20px; text-align: center; }
    </style></head><body>" >> "$index_file"
    echo "<h1>Previews for <code>$base_path</code></h1>" >> "$index_file"
    echo "<ul>" >> "$index_file"

    count=0
    for hash_file in $(ls "$dest_dir"/*.hash 2>/dev/null); do
        safe_branch=$(basename "$hash_file" .hash)
        if [ -d "$dest_dir/$safe_branch" ]; then
            if [ "$bp_clean" = "/" ]; then
                link="/$safe_branch/"
            else
                link="$bp_clean/$safe_branch/"
            fi
            echo "<li><a href=\"$link\">$safe_branch</a></li>" >> "$index_file"
            count=$((count + 1))
        fi
    done

    if [ "$count" -eq 0 ]; then
        echo "<li>Aucune branche déployée pour le moment.</li>" >> "$index_file"
    fi

    echo "</ul>" >> "$index_file"
    echo "<div class=\"update-time\">Dernière mise à jour : $(date +'%d/%m/%Y %H:%M:%S')</div>" >> "$index_file"
    echo "</body></html>" >> "$index_file"
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
                VITE_BASE_PATH="$full_base_path" npm run build || { echo "Build échoué"; continue; }

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

        if [ "$is_active" = false ] && [ "$dir_name" != "index.html" ]; then
            echo "[$base_path] Nettoyage de la branche supprimée : '$dir_name'..."
            rm -rf "$dir"
            rm -f "$dest_dir/$dir_name.hash"
        fi
    done

    generate_index "$dest_dir" "$bp_clean" "$base_path"
}

while true; do
    if [ -f "$CONFIG_FILE" ]; then
        num_projects=$(jq '. | length' "$CONFIG_FILE")
        i=0
        while [ $i -lt "$num_projects" ]; do
            repo_url=$(jq -r ".[$i].REPO_URL" "$CONFIG_FILE")
            base_path=$(jq -r ".[$i].BASE_PATH" "$CONFIG_FILE")
            branch_regex=$(jq -r ".[$i].BRANCH_REGEX // \"\"" "$CONFIG_FILE")

            if [ "$repo_url" != "null" ] && [ "$base_path" != "null" ]; then
                sync_project "$repo_url" "$base_path" "$branch_regex" "proj_$i"
            fi
            i=$((i + 1))
        done
    elif [ -n "$REPO_URL" ] && [ -n "$BASE_PATH" ]; then
        sync_project "$REPO_URL" "$BASE_PATH" "$BRANCH_REGEX" "default"
    else
        echo "[$(date +'%H:%M:%S')] Aucune configuration trouvée."
    fi

    sleep "$INTERVAL_SECONDS"
done