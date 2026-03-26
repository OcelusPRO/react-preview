#!/bin/sh
# index_gen.sh - Génération de l'index HTML et du JSON des branches

. "$(dirname "$0")/utils.sh"

generate_index() {
    dest_dir="$1"
    bp_clean="$2"
    base_path="$3"
    json_file="$dest_dir/branches.json"
    index_file="$dest_dir/index.html"

    cp /template.html "$index_file"

    echo "{" > "$json_file"
    echo "  \"base_path\": \"$base_path\"," >> "$json_file"
    echo "  \"last_update\": \"$(date +'%Y-%m-%d %H:%M:%S')\"," >> "$json_file"
    echo "  \"branches\": [" >> "$json_file"

    first=true
    for hash_file in "$dest_dir"/*.hash; do
        [ -e "$hash_file" ] || continue
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
    echo "" >> "$json_file"
    echo "  ]" >> "$json_file"
    echo "}" >> "$json_file"
}

