#!/bin/sh

. "$(dirname "$0")/utils.sh"
. "$(dirname "$0")/index_gen.sh"

sync_project() {
    repo_url="$1"
    base_path="$2"
    branch_regex="$3"
    project_id="$4"

    bp_clean=$(clean_base_path "$base_path")
    dest_dir="/var/www/html$bp_clean"
    work_dir="/tmp/workdir/$project_id"

    mkdir -p "$dest_dir"
    mkdir -p "$work_dir"
    cd "$work_dir" || return

    unset GIT_ASKPASS
    unset _GIT_ASKPASS_TMP
    if [ -n "$GIT_TOKEN" ]; then
        _GIT_ASKPASS_TMP="/tmp/git_askpass_$$.sh"
        echo "#!/bin/sh" > "$_GIT_ASKPASS_TMP"
        echo "echo \"$GIT_TOKEN\"" >> "$_GIT_ASKPASS_TMP"
        chmod +x "$_GIT_ASKPASS_TMP"
        export GIT_ASKPASS="$_GIT_ASKPASS_TMP"
    fi

    if [ ! -d ".git" ]; then
        echo "[$base_path] Initial clone of the repository from <hidden-url>..."
        git clone "$repo_url" .
    fi

    echo "[$base_path] [$(date +'%H:%M:%S')] Checking for updates..."
    git fetch --all --prune --quiet

    active_safe_branches=""

    git branch -r | grep origin/ | grep -v HEAD | sed 's/origin\///' | while read -r branch; do
        [ -n "$branch_regex" ] && ! echo "$branch" | grep -Eq "$branch_regex" && continue
        safe_branch=$(safe_branch_name "$branch")
        active_safe_branches="$active_safe_branches $safe_branch"
        remote_hash=$(git rev-parse "origin/$branch")
        hash_file="$dest_dir/$safe_branch.hash"
        current_hash=""
        [ -f "$hash_file" ] && current_hash=$(cat "$hash_file")
        if [ "$remote_hash" != "$current_hash" ]; then
            echo "[$base_path] New version detected on branch '$branch' ($remote_hash)."
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
                echo "[$base_path] Building branch '$branch' with BASE=$full_base_path..."
                VITE_BASE_PATH="$full_base_path" npm run build -- --base="$full_base_path" || { echo "Build failed"; continue; }
                rm -rf "${dest_dir:?}/$safe_branch"
                mkdir -p "$dest_dir/$safe_branch"
                cp -r dist/* "$dest_dir/$safe_branch/" 2>/dev/null || true
                echo "$remote_hash" > "$hash_file"
                echo "[$base_path] Branch deployed at https://$DOMAIN$full_base_path"
            fi
        fi
    done

    for dir in "$dest_dir"/*/; do
        [ -d "$dir" ] || continue
        dir_name=$(basename "$dir")
        is_active=false
        for active_branch in $active_safe_branches; do
            [ "$dir_name" = "$active_branch" ] && is_active=true && break
        done
        if [ "$is_active" = false ] && [ "$dir_name" != "index.html" ] && [ "$dir_name" != "branches.json" ]; then
            echo "[$base_path] Cleaning up deleted branch: '$dir_name'..."
            rm -rf "$dir"
            rm -f "$dest_dir/$dir_name.hash"
        fi
    done

    if [ -n "$_GIT_ASKPASS_TMP" ] && [ -f "$_GIT_ASKPASS_TMP" ]; then
        rm -f "$_GIT_ASKPASS_TMP"
    fi

    generate_index "$dest_dir" "$bp_clean" "$base_path"
}

