let
  manifest = import ../manifest.nix;
  importTree =
    {
      lock,
      groups,
      manifest,
    }:
    let
      groupsX = manifest.groups or {};
      something = map (groupName: groupsX.${groupName}) groups;
      merged = builtins.zipAttrsWith (name: vs: builtins.concatMap (v: v.groups) vs) something;
    in
    builtins.mapAttrs (
      ident: lockEnt:
      let
        enabled = merged ? ${ident};
        source = fetchTree (

          (removeAttrs lockEnt.args [ "ref" ])
          // (removeAttrs lockEnt.locked [
            "lastModified"
            "lastModifiedDate"
            "shortRev"
          ])
        );
        depManifest = "${source}/manifest.nix";
        manifestExists = builtins.pathExists depManifest;
        optManifest = if manifestExists then import depManifest else { };

        scope = (
          importTree {
            groups = merged.${ident};
            manifest = optManifest;
            lock = lockEnt.dependencies;
          }
        );
        require = select: scope.${select};
      in
      if enabled then
        if manifestExists then
          optManifest.entrypoint { inherit require; }
        else
          import "${source}/default.nix"
      else
        throw ''
          You need to enable the correct groups
        ''
    ) lock;

  root = groups: manifest.entrypoint {
    require =
      select:
      (importTree {
        lock = (builtins.fromJSON (builtins.readFile ./lock.json));
        inherit manifest groups;
      }).${select};
  };
in
root
