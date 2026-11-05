#!/bin/zsh
# Mutation testing entry point (make mutate). Pass-through args: --files GLOB --max N --timeout S
exec python3 -I "$(dirname "$0")/mutate.py" "$@"
