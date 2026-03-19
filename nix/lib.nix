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

  splitString =
    sep: s:
    let
      splits = builtins.filter builtins.isString (builtins.split sep s);
    in
    splits;

  # Returns true if the path (or any ancestor) is marked for update
  shouldUpdatePath =
    path: updates:
    let
      result = builtins.foldl' (
        node: name:
        # A node along the path is litterly '{}'
        # Meaning the user wants to update recursively
        if node == { } then
          { }
        else if builtins.isAttrs node && node ? ${name} then
          node.${name}
        else
          "not-found"
      ) updates path;
    in
    result == null || result == { };
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
  /**
    Desugars `share` into a `transitiveOverrides` function.

    `share` is a list of dependency names to share transitively.
    It generates a function that overrides matching deps with the root's versions.

    If both `share` and `transitiveOverrides` are present,
    `share` is applied first, then `transitiveOverrides` on top.
  */
  shareToTransitiveOverrides =
    dependencies: shareList:
    let
      shared = builtins.listToAttrs (
        map (name: {
          inherit name;
          value = dependencies.${name};
        }) (builtins.filter (name: dependencies ? ${name}) shareList)
      );
    in
    deps: deps // shared;

  normalizeManifestOld =
    {
      defaultFn ? id,
    }:
    manifest:
    let
      dependencies = manifest.dependencies or { };
      share = manifest.share or [ ];
      hasShare = share != [ ];
      explicitTransitiveOverrides = manifest.transitiveOverrides or defaultFn;
      shareOverrides = shareToTransitiveOverrides dependencies share;

      # If both share and transitiveOverrides are set,
      # compose them: share first, then explicit on top
      combinedTransitiveOverrides =
        if hasShare then
          deps: explicitTransitiveOverrides (shareOverrides deps)
        else
          explicitTransitiveOverrides;
    in
    manifest
    // {
      dependencies = builtins.mapAttrs (
        n: dep:
        dep
        // {
          overrides = dep.overrides or (defaultFn);
        }
      ) dependencies;
      groups =
        manifest.groups or {
          eval = builtins.mapAttrs (n: v: [ "eval" ]) dependencies;
        };
      transitiveOverrides = combinedTransitiveOverrides;
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
          shouldUpdate = updateAll || shouldUpdatePath currPath updates;
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

  /**
    Adds defaults to the manifest

    Type: SomeAttrs -> {
      name: string;
      description;
      dependencies :: {
        url
        overrides
        pins
      };
      pins :: list [];
      share :: list [];
      entrypoint :: null | string;
    }
  */
  normalizeManifest =
    {
      defaultFn ? id,
    }:
    manifest:
    let
      dependencies = manifest.dependencies or { };
      checkName =
        name:
        builtins.seq (
          if builtins.match ".*/.*" name != null then
            let
              parts = splitString "/" name;
              suggested = builtins.concatStringsSep "-" parts;
            in
            throw "Invalid dependency name \"${name}\". \"/\" is not allowed. Try \"${suggested}\" instead."
          else
            null
        );
    in
    {
      name = manifest.name or "<unknown-project>";
      # Should we add a default?
      description = manifest.description or "";
      dependencies = builtins.mapAttrs (
        name: dep:
        checkName name {
          url = dep.url;
          overrides = dep.overrides or defaultFn;
          pins = dep.pins or [ ];
        }
      ) dependencies;
      pins = manifest.pins or [ ];
      share = manifest.share or [ ];
      entrypoint = manifest.entrypoint or "entrypoint.nix";
    };

  inherit (builtins)
    mapAttrs
    foldl'
    attrValues
    attrNames
    ;

  pathToLockKey = p: if p == [ ] then "" else "/" + builtins.concatStringsSep "/" p;

  resolve =
    {
      fetchTree,
      getDependencyManifest,
      currentLock,
      updates,
    }:
    rootManifest:
    let
      result = resolveNode {
        inherit
          fetchTree
          getDependencyManifest
          updates
          currentLock
          ;
        manifest = rootManifest;
        path = [ ];
        dedup = { };
        lockEntries = { };
        depGraph = { };
      };
    in
    {
      sources = result.lockEntries;
      deps = result.depGraph;
    };

  /**
    Resolves a single node's dependencies using a two-pass approach:

    Pass 1: Fetch all direct children, collecting lock entries, dedup info, and sources.
    Pass 2: Recurse into each child.

    The two passes are intentional. pass 1 must complete before pass 2 so that
    the parent set of resolved dependencies is known. This is required for
    `share` and `pins`: a parent declaring `share = [ "A" ]` needs its own locked
    version of "A" before recursing, so it can inject it into all children.
  */
  resolveNode =
    {
      fetchTree,
      getDependencyManifest,
      manifest,
      path,
      dedup,
      lockEntries,
      depGraph,
      updates,
      currentLock,
    }:
    let
      updateAll = updates == { };
      normalized = normalizeManifest { } manifest;
      depNames = attrNames normalized.dependencies;

      /*
        Pass1
        Perform a first pass over all direct children

        Collecting the following:

        {
          lockEntries :: { lockKey -> lockEntry } # goes into lockfile
          dedup :: { narHash -> lockKey } # for narHash dedup lookup
          depToKey :: { depName -> lockKey } # for deps.${parentLockKey}
          sources :: { depName -> outPath } # to read child manifests
        }
      */
      collected =
        foldl'
          (
            acc: name:
            let
              dep = normalized.dependencies.${name};
              currPath = path ++ [ name ];

              inherit (dep) url;
              fetchTreeArgs = (builtins.parseFlakeRef url) // (dep.args or { });
              fetchResult = fetchTree fetchTreeArgs;

              narHash = fetchResult.narHash;
              isDuplicate = acc.dedup ? ${narHash};
              # Why use "name" as lockKey?
              # - Not every dependency has a mana.nix, so there's no guaranteed canonical name
              # - The same package can be depended on under different names by different consumers
              # - The consumer's name is always available, no conditional logic needed
              # LockKey collisions cannot happen
              # Every dependency maps to a unique LockKey
              # Collisions can only happen if the name is allowed to contain the seperator "/"
              # since the LocKey is checked this cannot happen
              pathKey = pathToLockKey currPath;
              lockKey = if isDuplicate then acc.dedup.${narHash} else pathKey;

              shouldUpdate = updateAll || shouldUpdatePath currPath updates || !currentLock.sources ? ${lockKey};

              dotPath = builtins.concatStringsSep "." currPath;

              lockKeyToPathKey =
                lockKey: builtins.concatStringsSep "." (splitString "/" (builtins.substring 1 (-1) lockKey));

              printUpdateInfo = builtins.trace (
                if isDuplicate then
                  if shouldUpdate then
                    "↑ updating: ${lockKeyToPathKey acc.dedup.${narHash}} (requested via ${dotPath})"
                  else
                    "- skipped: ${dotPath}"
                else if shouldUpdate then
                  "↑ updating: ${dotPath}"
                else
                  "- skipped: ${dotPath}"
              );
            in
            printUpdateInfo {
              sources = acc.sources // {
                ${name} = fetchResult.outPath;
              };
              depToKey = acc.depToKey // {
                ${name} = lockKey;
              };
              lockEntries =
                if isDuplicate then
                  # Did the user request an update?
                  # If yes we need to find the key via which it was deduplicated
                  if shouldUpdate then
                    let
                      sharedKey = acc.dedup.${narHash};
                    in
                    acc.lockEntries
                    // {
                      ${sharedKey} = {
                        locked = removeAttrs fetchResult [ "outPath" ];
                        args = fetchTreeArgs;
                      };
                    }
                  else
                    acc.lockEntries
                else if shouldUpdate then
                  acc.lockEntries
                  // {
                    ${lockKey} = {
                      locked = removeAttrs fetchResult [ "outPath" ];
                      args = fetchTreeArgs;
                    };
                  }
                else
                  acc.lockEntries
                  // {
                    ${lockKey} = currentLock.sources.${lockKey};
                  };
              dedup =
                if isDuplicate then
                  acc.dedup
                else
                  acc.dedup
                  // {
                    ${narHash} = lockKey;
                  };
            }
          )
          {
            inherit
              lockEntries # { lockKey -> lockEntry } - goes into lockfile
              dedup
              ; # { narHash -> lockKey } - reverse lookup
            depToKey = { }; # { depName -> lockKey } - for deps.${parentLockKey}
            sources = { }; # { depName -> outPath } - for pass2 to read child manifests
          }
          depNames;

      # Pass 2: recurse into children
      recursed =
        foldl'
          (
            acc: name:
            let
              currPath = path ++ [ name ];

              source = collected.sources.${name};
              rawChildManifest = getDependencyManifest source;
              # lockKey = collected.depToKey.${name};

              dep = normalized.dependencies.${name};
              # Apply overrides on raw deps, then let recursive call normalize
              overriddenDeps = dep.overrides (rawChildManifest.dependencies or { });
              childManifest = rawChildManifest // {
                dependencies = overriddenDeps;
              };

              recurse = resolveNode {
                path = currPath;
                inherit
                  fetchTree
                  getDependencyManifest
                  updates
                  currentLock
                  ;
                manifest = childManifest;
                inherit (acc) dedup lockEntries depGraph;
              };
            in
            {
              inherit (recurse) lockEntries dedup depGraph;
            }
          )
          {
            inherit (collected) lockEntries dedup;
            inherit depGraph;
          }
          depNames;

    in
    {
      inherit (recursed) lockEntries dedup;
      depGraph =
        recursed.depGraph
        // (if collected.depToKey == { } then { } else { ${pathToLockKey path} = collected.depToKey; });
    };
}
