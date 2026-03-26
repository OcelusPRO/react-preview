#!/bin/sh

generate_nginx_conf() {
    conf_file="/etc/nginx/http.d/default.conf"
    tmp_conf="/tmp/default.conf.tmp"

    echo "server {" > "$tmp_conf"
    echo "    listen 80;" >> "$tmp_conf"
    echo "    root /var/www/html;" >> "$tmp_conf"
    echo "    index index.html;" >> "$tmp_conf"

    find /var/www/html -type f -name "branches.json" | while read -r branches_file; do
        project_dir=$(dirname "$branches_file")

        find "$project_dir" -maxdepth 1 -type f -name "*.hash" | while read -r hash_file; do
            branch_name=$(basename "$hash_file" .hash)
            branch_dir="$project_dir/$branch_name"

            if [ -d "$branch_dir" ]; then
                branch_loc=$(echo "$branch_dir" | sed 's|^/var/www/html||')

                echo "    location $branch_loc/ {" >> "$tmp_conf"
                echo "        try_files \$uri \$uri/ $branch_loc/index.html;" >> "$tmp_conf"
                echo "    }" >> "$tmp_conf"
            fi
        done
    done

    echo "    location / {" >> "$tmp_conf"
    echo "        try_files \$uri \$uri/ /index.html =404;" >> "$tmp_conf"
    echo "    }" >> "$tmp_conf"

    echo "}" >> "$tmp_conf"

    if ! cmp -s "$tmp_conf" "$conf_file"; then
        mv "$tmp_conf" "$conf_file"
        nginx -s reload 2>/dev/null || true
        echo "⚙️ Configuration Nginx rechargée (Routage SPA ciblé appliqué)."
    fi
}