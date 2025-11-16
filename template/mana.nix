# '<YOUR PROJECT>' - Manifest
# --------------------
{
  entrypoint = ./entrypoint.nix;

  dependencies = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };
}