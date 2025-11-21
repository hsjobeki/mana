let
  lib = import ./lib.nix;
  inherit (lib) fetchLockEntries';
  makeMockFetchTree =
    sources: args:
    let
      key =
        if args ? owner && args ? repo then
          "${args.owner}/${args.repo}/${args.ref or "main"}"
        else
          args.url or (throw "Cannot create key from: ${builtins.toJSON args}");
    in
    if sources ? ${key} then sources.${key} else throw "Mock fetchTree: unknown source '${key}'";

  # Mock getDependencyManifest - returns manifest for a fetch result
  makeMockGetDependencyManifest =
    manifests: fetchResult:
    if manifests ? ${fetchResult.outPath} then
      lib.normalizeManifest { } manifests.${fetchResult.outPath}
    else
      lib.normalizeManifest { } { }; # Empty manifest
in
{
  # Simple
  test_simple-single-dependency =
    let
      mockSources = {
        "nixos/nixpkgs/nixos-unstable" = {
          outPath = "/nix/store/nixpkgs-unstable";
          rev = "abc123";
          narHash = "sha256-fake";
        };
      };

      mockManifests = {
        "/nix/store/nixpkgs-unstable" = {
          dependencies = { };
        };
      };

      fetchLockEntries = fetchLockEntries' {
        fetchTree = makeMockFetchTree mockSources;
        getDependencyManifest = makeMockGetDependencyManifest mockManifests;
        # Updates all
        updates = { };
        self = fetchLockEntries;
      };

      # mana.nix
      rootManifest = lib.normalizeManifest { } {
        dependencies = {
          nixpkgs = {
            url = "github:nixos/nixpkgs/nixos-unstable";
          };
        };
      };
    in
    {
      expr = fetchLockEntries {
        path = [ ];
        lock = { };
        transitiveOverrides = { };
        transitiveOverrideMode = "lenient";
      } rootManifest;
      # expected lockfile
      expected = {
        nixpkgs = {
          args = {
            owner = "nixos";
            ref = "nixos-unstable";
            repo = "nixpkgs";
            type = "github";
          };
          dependencies = { };
          locked = {
            narHash = "sha256-fake";
            rev = "abc123";
          };
          url = "github:nixos/nixpkgs/nixos-unstable";
        };
      };
    };

  # nested mana dependencies
  test_dependency-chain =
    let
      mockSources = {
        "A/A/main" = {
          outPath = "/nix/store/A";
          rev = "abc123-a";
          narHash = "sha256-fake-a";
        };
        "B/B/main" = {
          outPath = "/nix/store/B";
          rev = "abc123-b";
          narHash = "sha256-fake-b";
        };
      };

      mockManifests = {
        "/nix/store/A" = {
          dependencies = {
            B.url = "github:B/B/main";
          };
        };
      };

      fetchLockEntries = fetchLockEntries' {
        fetchTree = makeMockFetchTree mockSources;
        getDependencyManifest = makeMockGetDependencyManifest mockManifests;
        # Updates all
        updates = { };
        self = fetchLockEntries;
      };

      # mana.nix
      rootManifest = lib.normalizeManifest { } {
        dependencies = {
          A.url = "github:A/A/main";
        };
      };
    in
    {
      expr = fetchLockEntries {
        path = [ ];
        lock = { };
        transitiveOverrides = { };
        transitiveOverrideMode = "lenient";
      } rootManifest;
      # expected lockfile
      expected = {
        A = {
          args = {
            owner = "A";
            ref = "main";
            repo = "A";
            type = "github";
          };
          dependencies = {
            B = {
              args = {
                owner = "B";
                ref = "main";
                repo = "B";
                type = "github";
              };
              dependencies = { };
              locked = {
                narHash = "sha256-fake-b";
                rev = "abc123-b";
              };
              url = "github:B/B/main";
            };
          };
          locked = {
            narHash = "sha256-fake-a";
            rev = "abc123-a";
          };
          url = "github:A/A/main";
        };
      };
    };
  # sparse update
  test_sparse-update =
    let
      mockSources = {
        "A/A/main" = {
          outPath = "/nix/store/A";
          rev = "abc123-new";
          narHash = "sha256-fake-new";
        };
        "B/B/main" = {
          outPath = "/nix/store/B";
          rev = "abc123-new";
          narHash = "sha256-fake-new";
        };
      };

      mockManifests = {
        "/nix/store/A" = {
          dependencies = {
            B.url = "github:B/B/main";
          };
        };
      };

      fetchLockEntries = fetchLockEntries' {
        fetchTree = makeMockFetchTree mockSources;
        getDependencyManifest = makeMockGetDependencyManifest mockManifests;
        # Updates A.B
        # but not A
        updates = {
          A.B = null;
        };
        self = fetchLockEntries;
      };

      # mana.nix
      rootManifest = lib.normalizeManifest { } {
        dependencies = {
          A.url = "github:A/A/main";
        };
      };
    in
    {
      expr = fetchLockEntries {
        path = [ ];
        lock = {
          A = {
            args = {
              owner = "A";
              ref = "main";
              repo = "A";
              type = "github";
            };
            dependencies = {
              B = {
                args = {
                  owner = "B";
                  ref = "main";
                  repo = "B";
                  type = "github";
                };
                dependencies = { };
                locked = {
                  narHash = "sha256-fake-b";
                  rev = "abc123-b";
                };
                url = "github:B/B/main";
              };
            };
            locked = {
              narHash = "sha256-fake-a";
              rev = "abc123-a";
            };
            url = "github:A/A/main";
          };
        };
        transitiveOverrides = { };
        transitiveOverrideMode = "lenient";
      } rootManifest;
      # expected lockfile
      expected = {
        A = {
          args = {
            owner = "A";
            ref = "main";
            repo = "A";
            type = "github";
          };
          dependencies = {
            B = {
              args = {
                owner = "B";
                ref = "main";
                repo = "B";
                type = "github";
              };
              dependencies = { };
              locked = {
                narHash = "sha256-fake-new";
                rev = "abc123-new";
              };
              url = "github:B/B/main";
            };
          };
          locked = {
            narHash = "sha256-fake-a";
            rev = "abc123-a";
          };
          url = "github:A/A/main";
        };
      };
    };
}
