{ writeShellApplication }: writeShellApplication {
  name = "mana";
  text = ''
    #!/usr/bin/env bash

    set -efu -o pipefail

    NIX_SOURCE_FILES="${../../template}"

    function init() {
        set -efu -o pipefail

        # Enable globbing for the copy command
        set +f
        cp -rf "$NIX_SOURCE_FILES"/* .

        mkdir -p nix
        cp ${../../nix/importer.nix} ./nix/importer.nix
        echo "Mana initialized 💎"
        chmod -R +w .
    }

    function update() {
        set -efu -o pipefail
        local nix_attrset

        if [ $# -eq 0 ]; then
            nix_attrset=$(printf '{ }')
            echo "Updating all dependencies"
        else
            nix_attrset=$(printf '{ %s}' "$(printf '%s = null; ' "$@")")
            echo "Updating dependencies: $*"
        fi


        # Convert arguments to Nix attrset: { "foo" = null; "bar" = null; }
        nix --extra-experimental-features nix-command eval --refresh --json \
            --arg cwd "$(pwd)" \
            --arg updates "$nix_attrset" \
            -f ${../..}/scripts/update.nix \
            result \
            | jq -S '.' > next_lock.json

        # verify the next lock file
        if jq -e . next_lock.json > /dev/null 2>&1; then
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
        update)
            shift
            update "$@"
            ;;
        *)
            echo "Usage: $0 {init|update}"
            exit 1
            ;;
    esac
  '';
}
