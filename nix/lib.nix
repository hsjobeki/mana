rec {

  getAttrByPath =
    path: default: attrs:
    let
      go =
        ns: attrs:
        if builtins.length ns > 0 then
          if attrs ? ${builtins.head ns} then go (builtins.tail ns) attrs.${builtins.head ns} else default
        else
          attrs;
    in
    go path attrs;

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
    {
      defaultFn ? id,
    }:
    manifest:
    manifest
    // {
      # dependencies = manifest.dependencies or {};
      dependencies = builtins.mapAttrs (
        n: dep:
        dep
        // {
          overrides = dep.overrides or (defaultFn);
        }
      ) (manifest.dependencies or { });
      groups =
        manifest.groups or {
          eval = builtins.mapAttrs (n: v: [ "eval" ]) (manifest.dependencies or { });
        };
      transitiveOverrides = manifest.transitiveOverrides or (defaultFn);
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
      let
        local = localOverrideFn baseDeps;
      in
      rec {
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

  # Parametrized for better unit-testing
  fetchLockEntries' =
    {
      fetchTree,
      getDependencyManifest,
      self,
      updates,
    }:
    ctx: manifest:
    let
      updateAll = updates == { };
      # { <name> :: [ "eval" ... ] }
      enabledGroupsFor = builtins.zipAttrsWith (n: vs: builtins.concatLists vs) (
        builtins.attrValues manifest.groups
      );

      mapped = builtins.mapAttrs (
        ident: enabledGroups:
        let
          spec = manifest.dependencies.${ident};

          currPath = ctx.path ++ [ ident ];
          shouldUpdate = updateAll || (getAttrByPath currPath {} updates == null);
          # ---
          inherit (spec) url;
          fetchTreeArgs = (builtins.parseFlakeRef url) // (spec.args or { });
          fetchResult = fetchTree fetchTreeArgs;

          # --- next manifest
          childManifest = getDependencyManifest fetchResult;

          combined = computeOverrides {
            mode = ctx.transitiveOverrideMode;
            localOverrideFn = manifest.dependencies.${ident}.overrides;
            transitiveOverrideFn = manifest.transitiveOverrides;
            ctxTransitiveOverrides = ctx.transitiveOverrides;
            baseDeps = childManifest.dependencies;
          };

          /**
            The manifest of the <ident> dependency
            with
              - groups enabled
              - dependencies overriden
          */
          enabledManifest = childManifest // {
            groups = filterAttrs (n: _: builtins.elem n enabledGroups) childManifest.groups;
            dependencies = combined.deps;
          };
          # --- correlated lock entry
          lockEnt = ctx.lock.${ident};
        in
        {
          args = fetchTreeArgs;
          locked =
            if shouldUpdate then
              removeAttrs fetchResult [ "outPath" ]
            else
              # If this should not update
              # Just return the locked entry
              lockEnt.locked;
          inherit url;

          dependencies = self {
            path = currPath;
            lock = ctx.lock.${ident}.dependencies or { };
            inherit (combined) transitiveOverrides;
            transitiveOverrideMode = "strict"; # transitiveOverrides > localOverrides
          } enabledManifest;
        }
      ) enabledGroupsFor;
    in
    mapped;
}
