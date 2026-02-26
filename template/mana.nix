# '<YOUR PROJECT>' - Manifest
# --------------------
{
  name = "<YOUR PROJECT>";
  # description = "";

  entrypoint = ./entrypoint.nix;

  dependencies = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  # Share these dependencies with all transitive dependencies.
  # Libraries that also depend on nixpkgs will use YOUR version.
  share = [ "nixpkgs" ];
}