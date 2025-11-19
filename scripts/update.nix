{
  cwd,
  updates ? { },
}:
let
  inherit (import ../nix/lib.nix)
    computeOverrides
    hasAttrPath
    filterAttrs
    normalizeManifest
    ;

  updateAll = updates == { };

  rootManifest = import (cwd + "/mana.nix");
  currentLock = builtins.fromJSON (builtins.readFile (cwd + "/lock.json"));

  go =
    ctx: manifest:
    let
      manifest' = normalizeManifest manifest;
      enabledGroupsFor = builtins.zipAttrsWith (n: vs: builtins.concatLists vs) (
        builtins.attrValues manifest'.groups
      );

      mapped = builtins.mapAttrs (
        ident: enabledGroups:
        let
          spec = manifest.dependencies.${ident};

          currPath = ctx.path ++ [ ident ];
          shouldUpdate = updateAll || hasAttrPath currPath updates;
          # ---
          inherit (spec) url;
          fetchTreeArgs = (builtins.parseFlakeRef url) // (spec.args or { });
          fetchResult = fetchTree fetchTreeArgs;

          # --- next manifest
          nestedManifestFile = "${fetchResult}/mana.nix";
          optManifestFile = if builtins.pathExists nestedManifestFile then import nestedManifestFile else { };

          nestedManifest = normalizeManifest optManifestFile;

          combined = computeOverrides {
            mode = ctx.transitiveOverrideMode;
            localOverrideFn = manifest.dependencies.${ident}.overrides;
            transitiveOverrideFn = manifest.transitiveOverrides;
            ctxTransitiveOverrides = ctx.transitiveOverrides;
            baseDeps = nestedManifest.dependencies;
          };

          /**
            The manifest of the <ident> dependency
            with
              - groups enabled
              - dependencies overriden
          */
          enabledManifest = nestedManifest // {
            groups = filterAttrs (n: _: builtins.elem n enabledGroups) nestedManifest.groups;
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

          dependencies = go {
            path = currPath;
            lock = ctx.lock.${ident}.dependencies or { };
            inherit (combined) transitiveOverrides;
            transitiveOverrideMode = "strict"; # transitiveOverrides > localOverrides
          } enabledManifest;
        }
      ) enabledGroupsFor;
    in
    mapped;

  result = go {
    path = [ ];
    lock = currentLock;
    transitiveOverrides = { };
    # Allow local overrides to propagate
    transitiveOverrideMode = "lenient"; # localOverrides > transitiveOverrides
  } (normalizeManifest rootManifest);

in
{
  inherit result;
}
