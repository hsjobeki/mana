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
        chmod +w -R .
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
        if [ $# -eq 0 ]; then
            echo "Usage: update <dep> [<dep2>] [<dep3>...]"
            echo "Example: update nixpkgs home-manager"
            return 1
        fi
        echo "Updating dependencies: $*"
        mkdir -p nix

        # Convert arguments to Nix attrset: { "foo" = null; "bar" = null; }
        local nix_attrset
        nix_attrset=$(printf '{ %s}' "$(printf '%s = null; ' "$@")")
        nix-instantiate --eval --strict --json \
            --arg cwd "$(pwd)" \
            --arg updates "$nix_attrset" \
            ${../../scripts/update.nix} \
            | jq -S '.' > next_lock.json

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