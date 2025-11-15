{ writeShellApplication }: writeShellApplication {
  name = "mana";
  text = ''
    #!/usr/bin/env bash

    set -e

    NIX_SOURCE_FILES="${../../assets}"

    function init() {
        cp "$NIX_SOURCE_FILES" ./.
        echo "Mana initialized 💎"
        chmod +w -R .
    }

    function lock() {
        echo "Generating mana lock.json ◇◇◇◇"
        mkdir -p nix
        nix-instantiate --eval --strict --json --arg cwd "$(pwd)" ${../../scripts/lock-update.nix} \
            | jq -S '.' > nix/lock.json
        chmod +w -R nix
        echo "lock.json updated"
    }

    case "$1" in
        init)
            init
            ;;
        lock)
            lock
            ;;
        *)
            echo "Usage: $0 {init|lock}"
            exit 1
            ;;
    esac
  '';
}