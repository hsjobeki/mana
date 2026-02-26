# mana manifest
{
  name = "mana";
  description = "Dependency locking and injection for Nix";

  entrypoint = ./entrypoint.nix;
  dependencies = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  groups = {
    # Mana is dependency free
    # nixpkgs is only here for development environments
    # !! Do not remove this line.
    # Eval needs to be marked as empty explicitly.
    eval = { };
    dev = {
      nixpkgs = [ ];
    };
  };
}
