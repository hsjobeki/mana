rec {
  entrypoint = ./entrypoint.nix;
  dependencies = {
    nixpkgs.url = "github:nixos/nixpkgs";
  };
  transitiveOverrides = {
    nixpkgs = dependencies.nixpkgs;
  };
  groups = {
    eval = {
      nixpkgs = [ ];
      dep1 = [ "b1" "b1" ];
    };
    dev = {
    };
  };
}