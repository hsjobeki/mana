# manifest dependencies, injected by the nix/importer.nix
# ↓ dependencies controlled by mana
{ nixpkgs }:
#
# - to test: nix repl -f default.nix
# - to pass an explicit system 'import default.nix { system = "x86_64-linux"; }'
#
# ↓ your parameters
{system ? builtins.currentSystem, ... }:
let
  pkgs = nixpkgs { inherit system; };
in
{
  hello = pkgs.hello;
  # ...more of your own stuff
}