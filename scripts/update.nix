{
  cwd,
  updates ? { },
}:
builtins.trace (builtins.deepSeq updates updates) (
let
  manifest = import (cwd + "/mana.nix");
  currentLock = builtins.fromJSON (builtins.readFile (cwd + /lock.json));
  /*
    Checks if a path of attribute names exists
  */
  hasAttrPath =
    path: attrs:
    let
      # result is { success = bool; current = attrset or null }
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

  collectLockEntries =
    ctx: manifest:
    builtins.mapAttrs (
      ident: spec:
      let
        currPath = ctx.path ++ [ ident ];
        shouldUpdate = hasAttrPath currPath updates;
        # ----
        inherit (spec) url;
        fetchTreeArgs = (builtins.parseFlakeRef url) // (spec.args or { });
        fetchResult = fetchTree fetchTreeArgs;
        nestedManifestFile = "${fetchResult}/mana.nix";
        optManifestFile = if builtins.pathExists nestedManifestFile then import nestedManifestFile else { };
        dependencies = collectLockEntries {
          path = currPath;
          lock = ctx.lock.${ident}.dependencies or { };
        } optManifestFile;
        # ----
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
        inherit url dependencies;
      }

    ) (manifest.dependencies or { });
  result = collectLockEntries {
    path = [ ];
    lock = currentLock;
  } manifest;
in
result
)