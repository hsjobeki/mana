{
  cwd,
  updates ? { },
}:
let
  debug = msg: v: builtins.trace "${msg} ${(builtins.toJSON v)}" v;

  updateAll = updates == { };

  rootManifest = import (cwd + "/mana.nix");
  currentLock = builtins.fromJSON (builtins.readFile (cwd + "/lock.json"));
  # Checks if a path of attribute names exists
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

  # genAttrs =
  #   list: f:
  #   builtins.listToAttrs (
  #     map (name: {
  #       inherit name;
  #       value = f name;
  #     }) list
  #   );

  filterAttrs =
    pred: set:
    removeAttrs set (builtins.filter (name: !pred name set.${name}) (builtins.attrNames set));

  validateMode =
    mode:
    let
      validModes = [
        "lenient"
        "strict"
      ];
    in
    if builtins.elem mode validModes then
      mode
    else
      throw ''
        Invalid transitiveOverrideMode: "${mode}"

        Valid modes are: ${builtins.concatStringsSep ", " (map (m: ''"${m}"'') validModes)}

        - "lenient": Local overrides take precedence over transitive overrides
        - "strict":  Transitive overrides take precedence over local overrides
      '';

  id = x: x;

  getManifest =
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

  go =
    ctx: manifest:
    # assert debug "${builtins.toJSON ctx.transitiveOverrides}" true;
    let
      manifest' = getManifest manifest;
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

          manifestWithDefaults = getManifest optManifestFile;

          mode = validateMode ctx.transitiveOverrideMode;

          combined =
            if mode == "strict" then
              rec {
                local = (manifest.dependencies.${ident}.overrides manifestWithDefaults.dependencies);
                transitiveOverrides = (manifest.transitiveOverrides local) // ctx.transitiveOverrides;
                deps = transitiveOverrides;
              }
            else if mode == "lenient" then
              rec {
                transitiveOverrides =
                  (manifest.transitiveOverrides manifestWithDefaults.dependencies) // ctx.transitiveOverrides;
                deps = manifest.dependencies.${ident}.overrides transitiveOverrides;
              }
            else
              # This branch should never happen
              # due to strictness of 'validateMode'
              abort "Unsupported overrideMode: ${mode}";

          enabledManifest = manifestWithDefaults // {

            groups = filterAttrs (n: _: builtins.elem n enabledGroups) manifestWithDefaults.groups;

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
  } (getManifest rootManifest);

in
{
  inherit result;
}
