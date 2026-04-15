let
  lib = import ./lib.nix;

  makeMockFetchTree =
    sources: args:
    let
      key =
        if args ? owner && args ? repo then
          "${args.owner}/${args.repo}/${args.ref or args.rev or "main"}"
        else
          args.url or (throw "Cannot create key from: ${builtins.toJSON args}");
    in
    if sources ? ${key} then sources.${key} else throw "Mock fetchTree: unknown source '${key}'";
in
{
  inherit lib;
  test_dedup_flat =
    let
      mockSources = {
        "owner/A/main" = {
          outPath = "/nix/store/dep-A";
          rev = "abc123";
          # same hash
          narHash = "sha256-fake-a";
        };
        "owner/B/main" = {
          outPath = "/nix/store/dep-B";
          rev = "abc123";
          # same hash
          narHash = "sha256-fake-a";
        };
      };

      rootManifest = {
        dependencies.A.url = "github:owner/A";
        dependencies.B.url = "github:owner/B";
      };

      getDependencyManifest =
        outPath:
        {
          "/nix/store/dep-A" = { };
          "/nix/store/dep-B" = { };
        }
        .${outPath};
    in
    {
      expr = lib.resolve {
        updates = { };
        currentLock = { };
        fetchTree = makeMockFetchTree mockSources;
        inherit getDependencyManifest;
      } rootManifest;
      expected = {
        deps = {
          "" = {
            A = "/A";
            B = "/A";
          };
        };
        sources = {
          "/A" = {
            args = {
              owner = "owner";
              repo = "B";
              type = "github";
            };
            locked = {
              narHash = "sha256-fake-a";
              rev = "abc123";
            };
          };
        };
      };
    };
  test_dedup_ref =
    let
      mockSources = {
        "owner/A/206b4ba6beddbb32ef2723007a6e04ccbf3e7bd0" = {
          outPath = "/nix/store/A-1";
          rev = "abc123";
          # same hash
          narHash = "sha256-fake-a";
        };
        "owner/A/branch" = {
          outPath = "/nix/store/A-1";
          rev = "abc123";
          # same hash
          narHash = "sha256-fake-a";
        };
      };

      rootManifest = {
        dependencies.A_1.url = "github:owner/A?rev=206b4ba6beddbb32ef2723007a6e04ccbf3e7bd0";
        dependencies.A_2.url = "github:owner/A?ref=branch";
      };

      getDependencyManifest =
        outPath:
        {
          "/nix/store/A-1" = { };
          "/nix/store/A-2" = { };
        }
        .${outPath};
    in
    {
      expr = lib.resolve {
        updates = { };
        currentLock = { };
        fetchTree = makeMockFetchTree mockSources;
        inherit getDependencyManifest;
      } rootManifest;
      expected = {
        deps = {
          "" = {
            A_1 = "/A_1";
            A_2 = "/A_1";
          };
        };
        sources = {
          "/A_1" = {
            args = {
              owner = "owner";
              repo = "A";
              type = "github";
              ref = "branch";
            };
            locked = {
              narHash = "sha256-fake-a";
              rev = "abc123";
            };
          };
        };
      };
    };
  test_dedup_nested =
    let
      mockSources = {
        "owner/A/main" = {
          outPath = "/nix/store/dep-A";
          rev = "abc123";
          narHash = "sha256-fake-a";
        };
        "owner/B/main" = {
          outPath = "/nix/store/dep-B";
          rev = "abc123";
          narHash = "sha256-fake-b";
        };
        "owner/C/main" = {
          outPath = "/nix/store/dep-C";
          rev = "abc123";
          narHash = "sha256-fake-a";
        };
      };

      rootManifest = {
        dependencies.A.url = "github:owner/A";
        dependencies.B.url = "github:owner/B";
      };

      getDependencyManifest =
        outPath:
        {
          "/nix/store/dep-A" = { };
          "/nix/store/dep-B" = {
            dependencies.C.url = "github:owner/C";
          };
          "/nix/store/dep-C" = { };
        }
        .${outPath};
    in
    {
      expr = lib.resolve {
        updates = { };
        currentLock = { };
        fetchTree = makeMockFetchTree mockSources;
        inherit getDependencyManifest;
      } rootManifest;
      expected = {
        deps = {
          "" = {
            A = "/A";
            B = "/B";
          };
          "/B" = {
            C = "/A";
          };
        };
        sources = {
          "/A" = {
            args = {
              owner = "owner";
              repo = "C";
              type = "github";
            };
            locked = {
              narHash = "sha256-fake-a";
              rev = "abc123";
            };
          };
          "/B" = {
            args = {
              owner = "owner";
              repo = "B";
              type = "github";
            };
            locked = {
              narHash = "sha256-fake-b";
              rev = "abc123";
            };
          };
        };
      };
    };
  test_dep_graph_nested =
    let
      mockSources = {
        "owner/A/main" = {
          outPath = "/nix/store/dep-A";
          rev = "abc123";
          narHash = "sha256-fake-a";
        };
        "owner/B/main" = {
          outPath = "/nix/store/dep-B";
          rev = "abc123";
          narHash = "sha256-fake-b";
        };
        "owner/C1/main" = {
          outPath = "/nix/store/dep-C1";
          rev = "abc123";
          narHash = "sha256-fake-c1";
        };
        "owner/C2/main" = {
          outPath = "/nix/store/dep-C2";
          rev = "abc123";
          narHash = "sha256-fake-c2";
        };
        "owner/D/main" = {
          outPath = "/nix/store/dep-D";
          rev = "abc123";
          narHash = "sha256-fake-d";
        };
      };

      rootManifest = {
        dependencies.A.url = "github:owner/A";
        dependencies.B.url = "github:owner/B";
      };

      getDependencyManifest =
        outPath:
        {
          "/nix/store/dep-A" = {
            dependencies.C.url = "github:owner/C2";
          };
          "/nix/store/dep-B" = {
            dependencies.C.url = "github:owner/C1";
          };
          "/nix/store/dep-C1" = {
            dependencies.D.url = "github:owner/D";
          };
          "/nix/store/dep-C2" = {
            dependencies.D.url = "github:owner/D";
          };
          "/nix/store/dep-D" = {
          };
        }
        .${outPath};
    in
    {
      expr = lib.resolve {
        updates = { };
        currentLock = { };
        fetchTree = makeMockFetchTree mockSources;
        inherit getDependencyManifest;
      } rootManifest;
      expected = {
        deps = {
          "" = {
            A = "/A";
            B = "/B";
          };
          "/A" = {
            C = "/A/C";
          };
          "/A/C" = {
            D = "/A/C/D";
          };
          "/B" = {
            C = "/B/C";
          };
          "/B/C" = {
            D = "/A/C/D";
          };
        };
        sources = {
          "/A" = {
            args = {
              owner = "owner";
              repo = "A";
              type = "github";
            };
            locked = {
              narHash = "sha256-fake-a";
              rev = "abc123";
            };
          };
          "/A/C" = {
            args = {
              owner = "owner";
              repo = "C2";
              type = "github";
            };
            locked = {
              narHash = "sha256-fake-c2";
              rev = "abc123";
            };
          };
          "/A/C/D" = {
            args = {
              owner = "owner";
              repo = "D";
              type = "github";
            };
            locked = {
              narHash = "sha256-fake-d";
              rev = "abc123";
            };
          };
          "/B" = {
            args = {
              owner = "owner";
              repo = "B";
              type = "github";
            };
            locked = {
              narHash = "sha256-fake-b";
              rev = "abc123";
            };
          };
          "/B/C" = {
            args = {
              owner = "owner";
              repo = "C1";
              type = "github";
            };
            locked = {
              narHash = "sha256-fake-c1";
              rev = "abc123";
            };
          };
        };
      };
    };
  test_dep_slash =
    let
      mockSources = {
        "owner/A-B/main" = {
          outPath = "/nix/store/dep-A-B";
          rev = "abc123";
          narHash = "sha256-fake-a-b";
        };
        "owner/A/main" = {
          outPath = "/nix/store/dep-A";
          rev = "abc123";
          narHash = "sha256-fake-a";
        };
        "owner/B/main" = {
          outPath = "/nix/store/dep-B";
          rev = "abc123";
          narHash = "sha256-fake-b";
        };
      };

      rootManifest = {
        dependencies."A".url = "github:owner/A";
        dependencies."B".url = "github:owner/B";
      };

      getDependencyManifest =
        outPath:
        {
          "/nix/store/dep-A" = {
            dependencies.B.url = "github:owner/B";
          };
          "/nix/store/dep-A-B" = {
            dependencies.B.url = "github:owner/B";
          };
          "/nix/store/dep-B" = {
            dependencies."A/B".url = "github:owner/A-B";
          };
        }
        .${outPath};
    in
    {
      expr = lib.resolve {
        updates = { };
        currentLock = { };
        fetchTree = makeMockFetchTree mockSources;
        inherit getDependencyManifest;
      } rootManifest;
      expectedError = {
        msg = ''Invalid dependency name "A/B"'';
      };
    };

  test_share =
    let
      mockSources = {
        "owner/nixpkgs/unstable" = {
          outPath = "/nix/store/nixpkgs";
          rev = "abc123";
          narHash = "sha256-fake-hash-unstable";
        };
        "owner/nixpkgs/25.11" = {
          outPath = "/nix/store/nixpkgs";
          rev = "abc123";
          narHash = "sha256-fake-hash-2511";
        };
        "owner/nixpkgs/26.05" = {
          outPath = "/nix/store/nixpkgs";
          rev = "abc123";
          narHash = "sha256-fake-hash-2605";
        };
        "owner/A/main" = {
          outPath = "/nix/store/dep-A";
          rev = "abc123";
          narHash = "sha256-fake-a";
        };
        "owner/B/main" = {
          outPath = "/nix/store/dep-B";
          rev = "abc123";
          narHash = "sha256-fake-b";
        };
        "owner/C/main" = {
          outPath = "/nix/store/dep-C";
          rev = "abc123";
          narHash = "sha256-fake-c";
        };
      };

      rootManifest = {
        dependencies."A".url = "github:owner/A";
        # dependencies."B".url = "github:owner/B";
        # Unstable shall be used for all!
        dependencies.nixpkgs.url = "github:owner/nixpkgs/unstable";
        shares = [ "nixpkgs" ];
      };

      getDependencyManifest =
        outPath:
        {
          "/nix/store/dep-A" = {
            dependencies.B.url = "github:owner/B";
            dependencies.nixpkgs.url = "github:owner/nixpkgs/25.11";
          };
          "/nix/store/nixpkgs" = {
            # dependencies.B.url = "github:owner/B";
          };
          "/nix/store/dep-B" = {
            dependencies."nixpkgs".url = "github:owner/nixpkgs/26.05";
            dependencies."C".url = "github:owner/C";
            shares = [
              "nixpkgs"
              "foo"
            ];
          };
          "/nix/store/dep-C" = {
            dependencies."nixpkgs".url = "github:owner/nixpkgs/26.05";
            shares = [
              "nixpkgs"
              "bar"
              "foo"
            ];
          };
        }
        .${outPath};
      result = lib.resolve {
        updates = { };
        currentLock = { };
        fetchTree = makeMockFetchTree mockSources;
        inherit getDependencyManifest;
      } rootManifest;

    in
    {
      expr = result;
      expected = {
        deps = {
          "" = {
            A = "/A";
            nixpkgs = "/nixpkgs";
          };
          "/A" = {
            B = "/A/B";
            nixpkgs = "/nixpkgs";
          };
          "/A/B" = {
            C = "/A/B/C";
            nixpkgs = "/nixpkgs";
          };
          "/A/B/C" = {
            nixpkgs = "/nixpkgs";
          };
        };
        sources = {
          "/A" = {
            args = {
              owner = "owner";
              repo = "A";
              type = "github";
            };
            locked = {
              narHash = "sha256-fake-a";
              rev = "abc123";
            };
          };
          "/A/B" = {
            args = {
              owner = "owner";
              repo = "B";
              type = "github";
            };
            locked = {
              narHash = "sha256-fake-b";
              rev = "abc123";
            };
          };
          "/A/B/C" = {
            args = {
              owner = "owner";
              repo = "C";
              type = "github";
            };
            locked = {
              narHash = "sha256-fake-c";
              rev = "abc123";
            };
          };
          "/nixpkgs" = {
            args = {
              owner = "owner";
              ref = "unstable";
              repo = "nixpkgs";
              type = "github";
            };
            locked = {
              narHash = "sha256-fake-hash-unstable";
              rev = "abc123";
            };
          };
        };
      };
    };

  test_pin =
    let
      mockSources = {
        "owner/nixpkgs/unstable" = {
          outPath = "/nix/store/nixpkgs";
          rev = "abc123";
          narHash = "sha256-fake-hash-unstable";
        };
        "owner/nixpkgs/25.11" = {
          outPath = "/nix/store/nixpkgs";
          rev = "abc123";
          narHash = "sha256-fake-hash-2511";
        };
        "owner/nixpkgs/26.05" = {
          outPath = "/nix/store/nixpkgs";
          rev = "abc123";
          narHash = "sha256-fake-hash-2605";
        };
        "owner/A/main" = {
          outPath = "/nix/store/dep-A";
          rev = "abc123";
          narHash = "sha256-fake-a";
        };
        "owner/B/main" = {
          outPath = "/nix/store/dep-B";
          rev = "abc123";
          narHash = "sha256-fake-b";
        };
        "owner/C/main" = {
          outPath = "/nix/store/dep-C";
          rev = "abc123";
          narHash = "sha256-fake-c";
        };
      };

      rootManifest = {
        dependencies."A".url = "github:owner/A";
        # dependencies."B".url = "github:owner/B";
        # Unstable shall be used for all!
        dependencies.nixpkgs.url = "github:owner/nixpkgs/unstable";
        shares = [ "nixpkgs" ];
      };

      getDependencyManifest =
        outPath:
        {
          "/nix/store/dep-A" = {
            dependencies.B.url = "github:owner/B";
            dependencies.nixpkgs.url = "github:owner/nixpkgs/25.11";
          };
          "/nix/store/nixpkgs" = {
            # dependencies.B.url = "github:owner/B";
          };
          "/nix/store/dep-B" = {
            dependencies."nixpkgs".url = "github:owner/nixpkgs/26.05";
            dependencies."C".url = "github:owner/C";
            shares = [
              "foo"
            ];
            pins = [
              "nixpkgs"
            ];
          };
          "/nix/store/dep-C" = {
            dependencies."nixpkgs".url = "github:owner/nixpkgs/25.11";
            shares = [ ];
          };
        }
        .${outPath};
      result = lib.resolve {
        updates = { };
        currentLock = { };
        fetchTree = makeMockFetchTree mockSources;
        inherit getDependencyManifest;
      } rootManifest;

    in
    {
      expr = result;
      expected = {
        deps = {
          "" = {
            A = "/A";
            nixpkgs = "/nixpkgs";
          };
          "/A" = {
            B = "/A/B";
            nixpkgs = "/nixpkgs";
          };
          "/A/B" = {
            C = "/A/B/C";
            nixpkgs = "/A/B/nixpkgs";
          };
          "/A/B/C" = {
            nixpkgs = "/A/B/C/nixpkgs";
          };
        };
        sources = {
          "/A" = {
            args = {
              owner = "owner";
              repo = "A";
              type = "github";
            };
            locked = {
              narHash = "sha256-fake-a";
              rev = "abc123";
            };
          };
          "/A/B" = {
            args = {
              owner = "owner";
              repo = "B";
              type = "github";
            };
            locked = {
              narHash = "sha256-fake-b";
              rev = "abc123";
            };
          };
          "/A/B/C" = {
            args = {
              owner = "owner";
              repo = "C";
              type = "github";
            };
            locked = {
              narHash = "sha256-fake-c";
              rev = "abc123";
            };
          };
          "/A/B/C/nixpkgs" = {
            args = {
              owner = "owner";
              ref = "25.11";
              repo = "nixpkgs";
              type = "github";
            };
            locked = {
              narHash = "sha256-fake-hash-2511";
              rev = "abc123";
            };
          };
          "/A/B/nixpkgs" = {
            args = {
              owner = "owner";
              ref = "26.05";
              repo = "nixpkgs";
              type = "github";
            };
            locked = {
              narHash = "sha256-fake-hash-2605";
              rev = "abc123";
            };
          };
          "/nixpkgs" = {
            args = {
              owner = "owner";
              ref = "unstable";
              repo = "nixpkgs";
              type = "github";
            };
            locked = {
              narHash = "sha256-fake-hash-unstable";
              rev = "abc123";
            };
          };
        };
      };
    };
}
