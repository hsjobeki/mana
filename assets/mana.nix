{
  entrypoint = { require }: import ./. {
    nixpkgs = require "nixpkgs";
  };
  dependencies = {
    nixpkgs.url = "github:nixos/nixpkgs";
  };
  groups = {
    eval = {
      nixpkgs = [];
    };
  };
}