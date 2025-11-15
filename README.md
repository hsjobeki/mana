# Mana 💎

Mana is a simple approach that solves dependency locking and injection in simple and effective way.

- Its only few lines of bash ⚡️ nix
- plural: Mana

## Init

```sh
nix run github:hsjobeki/mana -- init
```

This will create a all files to get you started:

- `mana.nix`: A manafest to describe your project
- `default.nix` Your default entrypoint for the nix cli and repl
  see [groups](#eval-groups) for what it does.

- `nix/importer.nix`: A vendored shim that
  takes care to inject the specified dependencies into the entrypoint

### Next Step: Lock all dependencies

```sh
nix run github:hsjobeki/mana -- lock
```

Creates a nix/lock.json that pins down all dependencies

Done ⚡️

To inspect

`nix repl -f default.nix`
```
> hello
«derivation /nix/store/f4yi9zbqnyld63j1bk89nqk7h409i0hh-hello.drv»
```

You should take a look at all files that exists. Before reading further

- `mana.nix`
- `entrypoint.nix`
- ...

---

## Eval Groups

When developing you often want to provide tools to others.
But at the same time you want to test and check using third party dependencies.
Your user shouldn't have to download your CI tooling by default.

That is a common painpoint with `flakes` currently leading to workarounds. In Mana this is a first class citizen.

Unless specified in the `mana.nix` all dependencies are in the `eval` group

```nix
# mana.nix
rec {
  entrypoint = ./entrypoint.nix;

  dependencies = {
    nixpkgs.url = "github:nixos/nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  groups = {
    eval = {
      nixpkgs = [ ];
    };
    dev = {
      treefmt-nix = [ "eval" "dev" ];
    };
  }
}
```

If you create a seperate `ci.nix`

```nix
# ci.nix
(import ./nix/importer.nix) [ "eval" "dev" ]
```

Using `default.nix`: `treefmt-nix` will contain an error that throws when acessed - But
using `ci.nix`: `treefmt-nix` will be present.

```nix
# entrypoint.nix
{nixpkgs, treefmt-nix }:
#
{system ? builtins.currentSystem }:
let
  pkgs = nixpkgs { inherit system; };
in
{
  packages.x = pkgs.callPackage ./. { };

  checks.x = pkgs.callPackage ./. { inherit treefmt-nix; };
}
```

## Dependency overrides

By default mana will respect the upstream manifest.
But it will initially re-lock all dependencies locally.

Often you want to reduce the number of nixpkgs downloads by forcing upstream to use your own version.

That can be done as follows:

```nix
# mana.nix
rec {
  entrypoint = ./entrypoint.nix;

  dependencies = {
    nixpkgs.url = "github:nixos/nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  transitiveOverrides = {
    nixpkgs = dependencies.nixpkgs;
  };
}
```

You can also apply granular overrides:

```nix
# mana.nix
rec {
  entrypoint = ./entrypoint.nix;

  dependencies = {
    nixpkgs.url = "github:nixos/nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.overrides = deps: deps // {
      nixpkgs = dependencies.nixpkgs;
    };
  };
}
```

---

💎
