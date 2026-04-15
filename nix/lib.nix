let
  inherit (builtins)
    # File system (side effects)
    pathExists
    # Pure eval
    attrNames
    attrValues
    concatStringsSep
    filter
    foldl'
    isAttrs
    isString
    listToAttrs
    mapAttrs
    match
    parseFlakeRef
    seq
    split
    substring
    toJSON
    trace
    ;

  /**
    Prints the message 'msg'
    and the value 'v' as json

    Returns the value 'v'
  */
  debug = msg: v: trace "${msg} ${(toJSON v)}" v;

  splitString =
    sep: s:
    let
      splits = filter isString (split sep s);
    in
    splits;

  /**
    filters an attribute set based on a predicate

    Vendored from nixpkgs
  */
  filterAttrs = pred: set: removeAttrs set (filter (name: !pred name set.${name}) (attrNames set));
  id = a: a;
  join = sep: concatStringsSep sep;

  # lock / path keys
  pathToLockKey = p: if p == [ ] then "" else "/" + join "/" p;
  lockKeyToPathKey = lockKey: join "." (splitString "/" (substring 1 (-1) lockKey));

  #
  # Returns true if the path (or any ancestor) is marked for update
  shouldUpdatePath =
    path: updates:
    let
      result = foldl' (
        node: name:
        # A node along the path is litterly '{}'
        # Meaning the user wants to update recursively
        if node == { } then
          { }
        else if isAttrs node && node ? ${name} then
          node.${name}
        else
          "not-found"
      ) updates path;
    in
    result == null || result == { };

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
      shares :: list [];
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
        seq (
          if match ".*/.*" name != null then
            let
              parts = splitString "/" name;
              suggested = concatStringsSep "-" parts;
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
      dependencies = mapAttrs (
        name: dep:
        checkName name {
          url = dep.url;
          overrides = dep.overrides or defaultFn;
          pins = dep.pins or [ ];
        }
      ) dependencies;
      pins = manifest.pins or [ ];
      shares = manifest.shares or [ ];
      entrypoint = manifest.entrypoint or "entrypoint.nix";
    };

  collectDependents =
    lockKey: deps:
    foldl' (
      res: pathKey:
      res
      ++ foldl' (
        acc: inputName:
        if deps.${pathKey}.${inputName} == lockKey then
          acc
          ++ [
            {
              name = pathKey;
              value = inputName;
            }
          ]
        else
          acc
      ) [ ] (attrNames deps.${pathKey})
    ) [ ] (attrNames deps);

  getDependencyManifest =
    source:
    let
      # This is not IFD, because source is from fetchTree
      # It should have the same performance impact however
      nestedManifestFile = "${source}/mana.nix";
      optManifestFile = if pathExists nestedManifestFile then import nestedManifestFile else { };

      nestedManifest = normalizeManifest { } optManifestFile;
    in
    nestedManifest;

  /**
    Resolves a single node's dependencies using a two-pass approach:

    Pass 1: Fetch all direct children, collecting lock entries, dedup info, and sources.
    Pass 2: Recurse into each child.

    The two passes are intentional. pass 1 must complete before pass 2 so that
    the parent set of resolved dependencies is known. This is required for
    `shares` and `pins`: a parent declaring `shares = [ "A" ]` needs its own locked
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
      shares,
      pins,
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
              fetchTreeArgs =
                if isShared && shares.${name} ? fetchTreeArgs && !pins ? ${name} then
                  shares.${name}.fetchTreeArgs
                else
                  (parseFlakeRef url) // (dep.args or { });

              fetchResult =
                if isShared && shares.${name} ? fetchResult && !pins ? ${name} then
                  shares.${name}.fetchResult
                else
                  fetchTree fetchTreeArgs;

              isShared = shares ? ${name};

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
              lockKey = if isDuplicate then acc.dedup.${narHash}.lockKey else pathKey;

              shouldUpdate = updateAll || shouldUpdatePath currPath updates || !currentLock.sources ? ${lockKey};

              dotPath = concatStringsSep "." currPath;

              # Enrich shares when we're the first to resolve a shared dep
              newShares =
                if isShared && !(shares.${name} ? fetchResult) then
                  acc.shares
                  // {
                    ${name} = shares.${name} // {
                      inherit fetchResult fetchTreeArgs;
                    };
                  }
                else
                  acc.shares;

              # printDebug = trace (''
              #   Locking: ${toJSON dotPath} to ${toJSON fetchResult.narHash}
              #   currentShares: ${toJSON (shares)}
              #   currentPins: ${toJSON (pins)}
              # '');

              printUpdateInfo = trace (
                if isDuplicate then
                  if shouldUpdate then
                    "↑ updating: ${lockKeyToPathKey acc.dedup.${narHash}.lockKey} (requested via ${dotPath})"
                  else
                    "- skipped: ${dotPath}"
                else if shouldUpdate then
                  "↑ updating: ${dotPath}"
                else
                  "- skipped: ${dotPath}"
              );
            in
            printUpdateInfo {
              shares = newShares;
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
                      sharedKey = acc.dedup.${narHash}.lockKey;
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
                    ${narHash} = { inherit lockKey fetchResult; };
                  };
            }
          )
          {
            inherit
              shares
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
              normalizedChildManifest = normalizeManifest { } childManifest;
              # lockKey = collected.depToKey.${name};

              dep = normalized.dependencies.${name};

              childShares = listToKeys currPath normalizedChildManifest.shares;
              nextShares = childShares // collected.shares;

              childPins = listToKeys currPath normalizedChildManifest.pins;
              nextPins = pins // childPins;

              # Apply overrides on raw deps, then let recursive call normalize
              overriddenDeps = dep.overrides (rawChildManifest.dependencies or { });
              childManifest = rawChildManifest // {
                dependencies = overriddenDeps;
              };
              # printDebug = trace (''
              #   Read child manifest of ${pathToLockKey currPath}
              #   recursing ${pathToLockKey currPath} with:
              #   childPins: ${toJSON childPins}

              #   nextPins: ${toJSON nextPins}
              # '');
              recurse = resolveNode {
                inherit
                  fetchTree
                  getDependencyManifest
                  updates
                  currentLock
                  ;
                path = currPath;
                shares = nextShares;
                pins = nextPins;
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

  listToKeys =
    path: shares:
    listToAttrs (
      map (name: {
        inherit name;
        value = {
          lockKey = pathToLockKey (path ++ [ name ]);
        };
      }) shares
    );

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
        shares = listToKeys [ ] rootManifest.shares or [ ];
        pins = listToKeys [ ] rootManifest.pins or [ ];
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
in
{
  inherit
    resolve
    getDependencyManifest
    normalizeManifest
    ;
}
