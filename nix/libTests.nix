let
  lib = import ./lib.nix;
in
{
  ##
  normalizeManifest = {
    test_empty = {
      expr = lib.normalizeManifest { defaultFn = "idFn"; } { };
      expected = {
        dependencies = { };
        groups = {
          eval = { };
        };
        transitiveOverrides = "idFn";
      };
    };
    test_no_groups = {
      expr = lib.normalizeManifest { defaultFn = "idFn"; } {
        dependencies = {
          A.url = "a:a";
        };
      };
      expected = {
        dependencies = {
          A.url = "a:a";
          A.overrides = "idFn";
        };
        groups = {
          eval = {
            A = [ "eval" ];
          };
        };
        transitiveOverrides = "idFn";
      };
    };
    test_explicit_groups = {
      expr = lib.normalizeManifest { defaultFn = "idFn"; } {
        dependencies = {
          A.url = "a:a";
        };
        groups = {
          eval = {
            A = [ "eval" ];
          };
        };
      };
      expected = {
        dependencies = {
          A.url = "a:a";
          A.overrides = "idFn";
        };
        groups = {
          eval = {
            A = [ "eval" ];
          };
        };
        transitiveOverrides = "idFn";
      };
    };
    test_overrides = {
      expr = lib.normalizeManifest { defaultFn = "idFn"; } {
        dependencies = {
          A.url = "a:a";
          A.overrides = "local";
        };
        transitiveOverrides = "global";
      };
      expected = {
        dependencies = {
          A.url = "a:a";
          A.overrides = "local";
        };
        groups = {
          eval = {
            A = [ "eval" ];
          };
        };
        transitiveOverrides = "global";
      };
    };
  };

  ##
  computeOverrides = {
    test_no_op = {
      expr = lib.computeOverrides {
        mode = "strict";
        localOverrideFn = deps: deps;
        transitiveOverrideFn = deps: deps;
        ctxTransitiveOverrides = { };
        baseDeps = { };
      };
      expected = {
        deps = { };
        transitiveOverrides = { };
      };
    };
    test_lenient = {
      expr = lib.computeOverrides {
        mode = "lenient";
        baseDeps = {
          a = "A";
          b = "B";
          c = "C";
        };
        localOverrideFn =
          deps:
          deps
          // {
            a = "local";
          };
        transitiveOverrideFn =
          deps:
          deps
          // {
            a = "transitive";
            b = "transitive";
          };
        ctxTransitiveOverrides = {
          a = "ctx";
          c = "ctx";
        };
      };
      expected = {
        deps = {
          a = "local";
          b = "transitive";
          c = "ctx";
        };
        transitiveOverrides = {
          a = "ctx";
          b = "transitive";
          c = "ctx";
        };
      };
    };
    test_strict = {
      expr = lib.computeOverrides {
        mode = "strict";
        baseDeps = {
          a = "A";
          b = "B";
          c = "C";
        };
        localOverrideFn =
          deps:
          deps
          // {
            a = "local";
          };
        transitiveOverrideFn =
          deps:
          deps
          // {
            a = "transitive";
            b = "transitive";
          };
        ctxTransitiveOverrides = {
          a = "ctx";
          c = "ctx";
        };
      };
      expected = {
        deps = {
          a = "ctx";
          b = "transitive";
          c = "ctx";
        };
        transitiveOverrides = {
          a = "ctx";
          b = "transitive";
          c = "ctx";
        };
      };
    };
    test_preserve = {
      expr = lib.computeOverrides {
        mode = "strict";
        baseDeps = {
          a = "A";
          b = "B";
          c = "C";
        };
        localOverrideFn = deps: deps;
        transitiveOverrideFn =
          deps:
          deps
          // {
            b = "transitive";
          };
        ctxTransitiveOverrides = {
          c = "ctx";
        };
      };
      expected = {
        deps = {
          a = "A";
          b = "transitive";
          c = "ctx";
        };
        transitiveOverrides = {
          a = "A";
          b = "transitive";
          c = "ctx";
        };
      };
    };
  };

  ##
  fetchLockEntries = import ./lock-tests.nix;
}
