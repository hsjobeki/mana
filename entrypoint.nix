# manifest dependencies, injected by the nix/importer.nix
{nixpkgs , ... }:
# - to test: nix repl -f default.nix
# - to pass an explicit system 'import default.nix { system = "x86_64-linux"; }'
{system ? builtins.currentSystem }:
let
  pkgs = nixpkgs { inherit system; };
in
{
  mana = pkgs.callPackage ./packages/mana { };
}