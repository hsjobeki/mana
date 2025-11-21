# mana manifest
{
  entrypoint = ./entrypoint.nix;
  dependencies = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  groups = {
    eval = {
      # Mana will become nixpkgs-free
      nixpkgs = [ ];
    };
    dev = {
      nixpkgs = [ ];
    };
  };
}
