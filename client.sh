#!/bin/sh
#
# Manage Xray clients and generate connection strings

CADDY_CONFIG=caddy/Caddyfile
XRAY_CONFIG=xray/config.json

add() {
    email="$1"

    if email_exists "$email"; then
        echo "$email is taken" >&2
        exit 1
    fi

    level=0
    uuid="$(cat /proc/sys/kernel/random/uuid)"

    client="$(jq --arg email "$email" --arg id "$uuid" --arg level "$level" --compact-output --null-input '$ARGS.named')"

    jq \
        --indent 4 \
        --sort-keys \
        ".inbounds[0].settings.clients += [$client]" "$XRAY_CONFIG" > "$XRAY_CONFIG".tmp && \
        mv "$XRAY_CONFIG".tmp "$XRAY_CONFIG"
}

connstr() {
    email="$1"

    if ! email_exists "$email"; then
        echo "No client with email $email" >&2
        exit 1
    fi

    domain="$(grep -E '^\S+ \{' "$CADDY_CONFIG" | cut -d ' ' -f 1)"
    uuid="$(jq --raw-output ".inbounds[0].settings.clients.[] | select(.email == \"$email\") | .id" "$XRAY_CONFIG")"

    jq \
        --arg add "$domain" \
        --arg aid 0 \
        --arg alpn h3 \
        --arg host "$domain" \
        --arg id "$uuid" \
        --arg net xhttp \
        --arg path /xhttp \
        --arg port 443 \
        --arg ps "$domain" \
        --arg tls tls \
        --arg type none \
        --arg v 2 \
        --compact-output \
        --null-input \
        '$ARGS.named' | \
        base64 --wrap=0 | \
        xargs --null printf 'vmess://%s\n'
}

email_exists() {
    email="$1"

    output="$(jq ".inbounds[0].settings.clients.[].email | select(. == \"$email\")" "$XRAY_CONFIG")"

    if [ -z "$output" ]; then
        return 1
    fi
}

list() {
    jq --raw-output '.inbounds[0].settings.clients.[] | .email' "$XRAY_CONFIG"
}

remove() {
    email="$1"

    if ! email_exists "$email"; then
        echo "No client with email $email" >&2
        exit 1
    fi

    jq \
        --indent 4 \
        --sort-keys \
        "del(.inbounds[0].settings.clients.[] | select(.email == \"$email\"))" "$XRAY_CONFIG" > "$XRAY_CONFIG".tmp && \
        mv "$XRAY_CONFIG".tmp "$XRAY_CONFIG"
}

usage() {
    echo 'Usage: client.sh {add EMAIL | connstr EMAIL | list | remove EMAIL}' >&2
}

if [ "$#" -eq 0 ]; then
    usage
    exit 1
fi

subcommand="$1"

if [ "$subcommand" = add ]; then
    if [ "$#" -ne 2 ]; then
        usage
        exit 1
    fi

    add "$2"
elif [ "$subcommand" = connstr ]; then
    if [ "$#" -ne 2 ]; then
        usage
        exit 1
    fi

    connstr "$2"
elif [ "$subcommand" = list ]; then
    if [ "$#" -ne 1 ]; then
        usage
        exit 1
    fi

    list
elif [ "$subcommand" = remove ]; then
    if [ "$#" -ne 2 ]; then
        usage
        exit 1
    fi

    remove "$2"
else
    usage
fi
