# manifest dependencies, injected by the nix/importer.nix
{ nixpkgs }:
# - to test: nix repl -f default.nix
# - to pass an explicit system 'import default.nix { system = "x86_64-linux"; }'
{
  system ? builtins.currentSystem,
}:
let
  bootstrapToolsForSystem = import ./binaries;
  writeShellApplication = import ./lib/write-shell-application.nix {
    inherit (bootstrapToolsForSystem.${system}) chmod mkdir;
    inherit system;
  };

  # Only for development
  pkgs = nixpkgs { inherit system; };
in
{
  # nix build -f . mana
  mana = import ./packages/mana { inherit writeShellApplication; };

  # nix shell -f dev.nix shell
  shell = pkgs.mkShell {
    packages = [
      pkgs.nix-unit
    ];
  };

  tests = import ./nix/libTests.nix;
}
