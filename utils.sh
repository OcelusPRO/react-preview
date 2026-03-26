#!/bin/sh

clean_base_path() {
    bp_clean="/$1"
    bp_clean=$(echo "$bp_clean" | sed 's|^/\+||;s|/\+$||;s|//|/|g')
    if [ "$bp_clean" != "/" ]; then
        bp_clean=$(echo "$bp_clean" | sed 's|/\+$||')
    fi
    echo "$bp_clean"
}

safe_branch_name() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9]/-/g' -e 's/^-//' -e 's/-$//'
}

