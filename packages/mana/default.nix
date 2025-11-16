{ writeShellApplication }: writeShellApplication {
  name = "mana";
  text = ''
    #!/usr/bin/env bash

    set -e

    NIX_SOURCE_FILES="${../../template}"

    function init() {
        cp -rf "$NIX_SOURCE_FILES"/* .
        mkdir -p nix
        cp ${../../nix/importer.nix} ./nix/importer.nix
        echo "Mana initialized 💎"
        chmod -R +w .
    }

    function lock() {
        echo "Generating mana lock.json ◇◇◇◇"
        mkdir -p nix
        nix-instantiate --eval --strict --json --arg cwd "$(pwd)" ${../../scripts/lock.nix} \
            | jq -S '.' > lock.json
        chmod +w -R nix
        echo "lock.json updated"
    }

    function update() {
        local nix_attrset

        if [ $# -eq 0 ]; then
            nix_attrset=$(printf '{ }')
            echo "Updating all dependencies"
        else
            nix_attrset=$(printf '{ %s}' "$(printf '%s = null; ' "$@")")
            echo "Updating dependencies: $*"
        fi


        # Convert arguments to Nix attrset: { "foo" = null; "bar" = null; }
        nix-instantiate --eval --strict --json \
            --arg cwd "$(pwd)" \
            --arg updates "$nix_attrset" \
            -A result \
            ${../../scripts/update.nix} \
            | jq -S '.' > next_lock.json

        mkdir -p nix
        # verify the next lock file
        if jq -e . next_lock.json > /dev/null 2>&1; then
            chmod +w next_lock.json lock.json
            mv next_lock.json lock.json
            echo "lock.json updated"
        else
            echo "Error: Generated invalid lock file"
            return 1
        fi
    }

    case "$1" in
        init)
            init
            ;;
        lock)
            lock
            ;;
        update)
            shift
            update "$@"
            ;;
        *)
            echo "Usage: $0 {init|lock|update}"
            exit 1
            ;;
    esac
  '';
}