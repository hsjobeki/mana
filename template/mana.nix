# Manifest
{
  # file that takes the dependencies
  entrypoint = ./entrypoint.nix;

  # The dependencies
  dependencies = {
    nixpkgs.url = "github:nixos/nixpkgs";
  };
}