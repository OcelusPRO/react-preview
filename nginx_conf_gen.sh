#!/bin/sh

generate_nginx_conf() {
    conf_file="/etc/nginx/http.d/default.conf"
    tmp_conf="/tmp/default.conf.tmp"

    echo "server {" > "$tmp_conf"
    echo "    listen 80;" >> "$tmp_conf"
    echo "    root /var/www/html;" >> "$tmp_conf"
    echo "    index index.html;" >> "$tmp_conf"

    find /var/www/html -type f -name "index.html" | awk '{ print length, $0 }' | sort -rn | cut -d" " -f2- | while read -r index_path; do
        dir_path=$(dirname "$index_path")

        is_project_root=false
        [ -f "$dir_path/branches.json" ] && is_project_root=true

        is_branch_root=false
        branch_name=$(basename "$dir_path")
        parent_dir=$(dirname "$dir_path")
        [ -f "$parent_dir/$branch_name.hash" ] && is_branch_root=true

        if [ "$is_project_root" = false ] && [ "$is_branch_root" = false ]; then
            continue
        fi

        location_path=$(echo "$dir_path" | sed 's|^/var/www/html||')
        [ -z "$location_path" ] && location_path="/"
        loc_route="$location_path"
        [ "$loc_route" != "/" ] && loc_route="$loc_route/"

        echo "    location $loc_route {" >> "$tmp_conf"
        echo "        try_files \$uri \$uri/ $location_path/index.html;" >> "$tmp_conf"
        echo "    }" >> "$tmp_conf"
    done

    echo "}" >> "$tmp_conf"

    if ! cmp -s "$tmp_conf" "$conf_file"; then
        mv "$tmp_conf" "$conf_file"
        nginx -s reload 2>/dev/null || true
        echo "⚙️ Nginx configuration reloaded dynamically."
    fi
}