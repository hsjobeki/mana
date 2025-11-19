rec {
  /**
    Checks if a path of attribute names exists

    Example:

    hasAttrPath [ "foo" "bar" ] { foo.bar = 1; }
    => true
  */
  hasAttrPath =
    path: attrs:
    let
      # result :: { success = bool; current = attrset; }
      result =
        builtins.foldl'
          (
            acc: part:
            if !acc.success then
              acc # already failed, pass through
            else if acc.current ? ${part} then
              {
                success = true;
                current = acc.current.${part};
              }
            else
              {
                success = false;
                current = null;
              }
          )
          {
            success = true;
            current = attrs;
          }
          path;
    in
    result.success;

  /**
    filters an attribute set based on a predicate

    Vendored from nixpkgs
  */
  filterAttrs =
    pred: set:
    removeAttrs set (builtins.filter (name: !pred name set.${name}) (builtins.attrNames set));

  id = x: x;

  /**
    Takes a manifest with optional fields and applies defaults

    Returns the normalized manifest where:

    ```
    NormalizedManifest :: {
      dependencies :: {
        <name> :: {
          overrides :: a -> a;
          ...
        };
      };
      groups :: {
        eval :: {
          <name> :: [ ]
        };
      };
      transitiveOverrides :: a -> a
    };
    ```
  */
  normalizeManifest =
    manifest:
    manifest
    // {
      # dependencies = manifest.dependencies or {};
      dependencies = builtins.mapAttrs (
        n: dep:
        dep
        // {
          overrides = dep.overrides or (id);
        }
      ) (manifest.dependencies or { });
      groups =
        manifest.groups or {
          eval = builtins.mapAttrs (n: v: [ "eval" ]) (manifest.dependencies or { });
        };
      transitiveOverrides = manifest.transitiveOverrides or (id);
    };

  /**
    Computes the next overrides based on the current overrides

    Returns an attribute set with `deps` and `transitiveOverrides`
  */
  computeOverrides =
    {
      mode,
      localOverrideFn,
      transitiveOverrideFn,
      ctxTransitiveOverrides,
      baseDeps,
    }:
    if mode == "strict" then
      rec {
        local = localOverrideFn baseDeps;
        transitiveOverrides = (transitiveOverrideFn local) // ctxTransitiveOverrides;
        deps = transitiveOverrides;
      }
    else if mode == "lenient" then
      rec {
        transitiveOverrides = (transitiveOverrideFn baseDeps) // ctxTransitiveOverrides;
        deps = localOverrideFn transitiveOverrides;
      }
    else
      let
        validModes = [
          "lenient"
          "strict"
        ];
      in
      throw ''
        Invalid transitiveOverrideMode: "${mode}"

        Valid modes are: ${builtins.concatStringsSep ", " (map (m: ''"${m}"'') validModes)}

        - "lenient": Local overrides take precedence over transitive overrides
        - "strict":  Transitive overrides take precedence over local overrides
      '';

  /**
    Prints the message 'msg'
    and the value 'v' as json

    Returns the value 'v'
  */
  debug = msg: v: builtins.trace "${msg} ${(builtins.toJSON v)}" v;
}
