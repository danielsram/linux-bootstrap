#!/usr/bin/env bash

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

append_if_missing() {
    grep -qxF "$1" "$2" || echo "$1" >> "$2"
}
