{ writeShellApplication }: writeShellApplication {
  name = "mana";
  text = ''
    set -efu -o pipefail

    NIX_SOURCE_FILES="${../../template}"

    function show_help() {
        cat <<'EOF'
mana 💎 - Dependency locking and injection for Nix

Commands:
  init      Initialize a new mana project in the current directory
  update    Update locked dependencies
  sync      Sync the local shim file(s) with the current mana version

Run 'mana <command> --help' for details.
EOF
    }

    function init() {
        set -efu -o pipefail

        if [[ "''${1:-}" == "--help" || "''${1:-}" == "-h" ]]; then
            cat <<'EOF'
Initialize a new mana project in the current directory.

Creates the following files:
mana.nix, entrypoint.nix, default.nix, nix/importer.nix.

Usage: mana init [--force]

Options:
  --force   Overwrite existing files
EOF
            return 0
        fi

        local force=0
        if [[ "''${1:-}" == "--force" ]]; then
            force=1
        fi
        # Enable globbing for the conflict check
        set +f

        # Check for conflicting files
        local conflicts=()
        for f in "$NIX_SOURCE_FILES"/*; do
            local target="./$(basename "$f")"
            if [ -e "$target" ]; then
                conflicts+=("$target")
            fi
        done
        if [ -e "./nix/importer.nix" ]; then
            conflicts+=("./nix/importer.nix")
        fi

        if [ "''${#conflicts[@]}" -gt 0 ] && [ "$force" -eq 0 ]; then
            echo "The following files already exist:"
            for f in "''${conflicts[@]}"; do
                echo "  $f"
            done
            echo ""
            echo "Use 'mana init --force' to overwrite."
            return 1
        fi

        # Proceed with copy
        cp -rf "$NIX_SOURCE_FILES"/* .

        mkdir -p nix
        cp ${../../nix/importer.nix} ./nix/importer.nix
        echo "Mana initialized 💎"
        chmod -R +w .
    }

    function update() {
        set -efu -o pipefail

        if [[ "''${1:-}" == "--help" || "''${1:-}" == "-h" ]]; then
            cat <<'EOF'
Update locked dependencies.

Usage: mana update [dep1 dep2 ...]

Examples:
  mana update            # update all
  mana update nixpkgs    # update only nixpkgs
EOF
            return 0
        fi

        local nix_attrset

        # Convert arguments to Nix attrset: { "foo" = null; "bar" = null; }
        if [ $# -eq 0 ]; then
            nix_attrset=$(printf '{ }')
            echo "Updating all dependencies"
        else
            nix_attrset=$(printf '{ %s}' "$(printf '%s = null; ' "$@")")
            echo "Updating dependencies: $*"
        fi

        # Call 'nix eval update.nix --json'
        nix --extra-experimental-features nix-command eval --refresh --raw \
            --arg cwd "$(pwd)" \
            --arg updates "$nix_attrset" \
            -f ${../..}/scripts/update.nix \
            result > next_lock.json

        # Verify the next lock file
        if nix-instantiate --eval -E "builtins.fromJSON (builtins.readFile ./next_lock.json)" > /dev/null 2>&1; then
            mv next_lock.json lock.json
            echo "lock.json updated"
        else
            echo "Error: Generated invalid lock file"
            return 1
        fi
    }

    function sync() {
        if [[ "''${1:-}" == "--help" || "''${1:-}" == "-h" ]]; then
            cat <<'EOF'
Sync the importer shim (nix/importer.nix) with the current mana version.

For upgrading your project get the latest version installed, then run this command.

Usage: mana sync
EOF
            return 0
        fi

        cp ${../../nix/importer.nix} ./nix/importer.nix
        echo "Importer shim updated 💎"
    }

    case "''${1:-}" in
        init)
            shift
            init "$@"
            ;;
        update)
            shift
            update "$@"
            ;;
        sync)
            shift
            sync "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        "")
            show_help
            ;;
        *)
            echo "Unknown command: ''${1}"
            echo ""
            show_help
            exit 1
            ;;
    esac
  '';
}
