#!/bin/sh

. "$(dirname "$0")/utils.sh"
. "$(dirname "$0")/index_gen.sh"
. "$(dirname "$0")/nginx_conf_gen.sh"

build_branch_async() {
    pending_file="$1"
    work_dir="$2"
    project_id="$3"
    dest_dir="$4"
    bp_clean="$5"
    base_path="$6"
    DOMAIN="$7"

    safe_branch=$(echo "$pending_file" | sed 's/.pending_//' | sed 's/.hash//')

    branch=$(cd "$work_dir" && git branch -r | grep origin/ | grep -v HEAD | sed 's/origin\///' | while read -r b; do
        if [ "$(safe_branch_name "$b")" = "$safe_branch" ]; then echo "$b"; break; fi
    done)

    remote_hash=$(cat "$work_dir/$pending_file")
    hash_file="$dest_dir/$safe_branch.hash"

    echo "[$base_path] 🚀 Starting parallel build for '$branch' ($remote_hash)..."

    branch_build_dir="/tmp/workdir/${project_id}_${safe_branch}_build"
    rm -rf "$branch_build_dir"

    cp -a "$work_dir" "$branch_build_dir"

    (
        cd "$branch_build_dir" || exit 1
        git checkout -B "$branch" "origin/$branch" --quiet

        if [ -f "package.json" ]; then
            if [ -f "package-lock.json" ]; then
                npm ci --silent --prefer-offline
            else
                npm install --silent --prefer-offline
            fi

            if [ "$bp_clean" = "/" ]; then
                full_base_path="/$safe_branch/"
            else
                full_base_path="$bp_clean/$safe_branch/"
            fi

            echo "[$base_path] ⚙️ Compiling '$branch' (BASE=$full_base_path)..."
            VITE_BASE_PATH="$full_base_path" npm run build -- --base="$full_base_path" || { echo "❌ Build failed for $branch"; exit 1; }

            rm -rf "${dest_dir:?}/$safe_branch"
            mkdir -p "$dest_dir/$safe_branch"
            cp -r dist/* "$dest_dir/$safe_branch/" 2>/dev/null || true

            echo "$remote_hash" > "$hash_file"
            echo "[$base_path] ✅ Branch deployed: https://$DOMAIN$full_base_path"
        fi
    )

    rm -rf "$branch_build_dir"
    rm -f "$work_dir/$pending_file"
}

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

    unset GIT_ASKPASS
    unset _GIT_ASKPASS_TMP
    if [ -n "$GIT_TOKEN" ]; then
        _GIT_ASKPASS_TMP="/tmp/git_askpass_$$.sh"
        echo "#!/bin/sh" > "$_GIT_ASKPASS_TMP"
        echo "echo \"$GIT_TOKEN\"" >> "$_GIT_ASKPASS_TMP"
        chmod +x "$_GIT_ASKPASS_TMP"
        export GIT_ASKPASS="$_GIT_ASKPASS_TMP"
    fi

    echo "[$base_path] [$(date +'%H:%M:%S')] Checking remote registry via ls-remote..."

    remote_refs=$(git ls-remote --heads "$repo_url")
    if [ -z "$remote_refs" ]; then
        echo "[$base_path] Failed to reach remote repository or repository is empty."
        return
    fi

    echo "$remote_refs" | while read -r remote_hash ref_name; do
        branch=$(echo "$ref_name" | sed 's|refs/heads/||')

        [ -n "$branch_regex" ] && ! echo "$branch" | grep -Eq "$branch_regex" && continue

        safe_branch=$(safe_branch_name "$branch")
        hash_file="$dest_dir/$safe_branch.hash"
        current_hash=""

        [ -f "$hash_file" ] && current_hash=$(cat "$hash_file")

        if [ "$remote_hash" != "$current_hash" ]; then
            echo "$remote_hash" > "$work_dir/.pending_${safe_branch}.hash"
        fi
    done

    needs_fetch=false
    for pending_file in "$work_dir"/.pending_*.hash; do
        if [ -f "$pending_file" ]; then
            needs_fetch=true
            break
        fi
    done

    if [ "$needs_fetch" = true ] || [ ! -d "$work_dir/.git" ]; then
        cd "$work_dir" || return

        if [ ! -d ".git" ]; then
            echo "[$base_path] Initial clone of the repository..."
            git clone "$repo_url" . --quiet
        else
            echo "[$base_path] Updates detected, fetching code..."
            git fetch --all --prune --quiet
        fi

        jobs_started=0
        for pending_file in .pending_*.hash; do
            [ -e "$pending_file" ] || continue
            build_branch_async "$pending_file" "$work_dir" "$project_id" "$dest_dir" "$bp_clean" "$base_path" "$DOMAIN" &
            jobs_started=$((jobs_started + 1))
        done

        if [ "$jobs_started" -gt 0 ]; then
            echo "[$base_path] Waiting for $jobs_started parallel build(s) to finish..."
            wait
            echo "[$base_path] All parallel builds finished."
        fi

        cd - > /dev/null || return
    fi

    all_active_safe_branches=$(echo "$remote_refs" | while read -r hash ref_name; do
        b=$(echo "$ref_name" | sed 's|refs/heads/||')
        [ -n "$branch_regex" ] && ! echo "$b" | grep -Eq "$branch_regex" && continue
        safe_branch_name "$b"
    done)

    for dir in "$dest_dir"/*/; do
        [ -d "$dir" ] || continue
        dir_name=$(basename "$dir")
        is_active=false

        for active_branch in $all_active_safe_branches; do
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
        generate_nginx_conf
}