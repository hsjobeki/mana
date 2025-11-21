let
  normalizeManifest =
    {
      defaultFn ? x: x,
    }:
    manifest:
    manifest
    // {
      # dependencies = manifest.dependenc ies or {};
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

  importTree =
    {
      lock,
      groups,
      manifest,
    }:
    let
      normalizedManifest = normalizeManifest { } manifest;
      availableGroups = normalizedManifest.groups;
      # { {groupName} }
      groupsByName = builtins.zipAttrsWith (name: vs: builtins.concatMap (v: v.groups) vs) (
        map (groupName: availableGroups.${groupName}) groups
      );
    in
    builtins.mapAttrs (
      ident: lockEnt:
      let
        enabled = groupsByName ? ${ident};
        source = fetchTree (
          (removeAttrs lockEnt.args [ "ref" ])
          // (removeAttrs lockEnt.locked [
            "lastModified"
            "lastModifiedDate"
            "shortRev"
          ])
        );
        depManifest = "${source}/mana.nix";
        manifestExists = builtins.pathExists depManifest;
        optManifest = if manifestExists then import depManifest else { };
        scope = (
          importTree {
            groups = groupsByName.${ident};
            manifest = optManifest;
            lock = lockEnt.dependencies;
          }
        );
      in
      if enabled then
        if manifestExists then
          let
            f = import optManifest.entrypoint;
          in
          f (builtins.intersectAttrs (builtins.functionArgs f) scope)
        else
          import "${source}/default.nix"
      else
        # Error handling
        # Collect diagnosis to help the user with group selection
        throw (
          let
            # Groups that include the missing dependency
            recommendedGroups = builtins.filter (group: availableGroups.${group} ? ${ident}) (
              builtins.attrNames availableGroups
            );
            hasGroups = availableGroups != [ ];
            # This should probably fail earlier?
            enabledGroups = if groups != [ ] then builtins.toString groups else "<None>";
          in
          if enabledGroups == [ ] then
            ''
              Cannot require dependency '${ident}' with no groups enabled.

              You called: (import ./nix/importer.nix) []

              To use dependencies, enable at least one group:
                (import ./nix/importer.nix) [ "eval" ]

              Available groups: ${builtins.toString (builtins.attrNames (availableGroups))}
            ''
          else if hasGroups then
            ''
              Dependency '${ident}' is not included into the current evaluation.

              Currently enabled groups: ${enabledGroups}

              To include '${ident}', add one of these groups:
                ${builtins.concatStringsSep "\n  " recommendedGroups}

              Example usage:
                (import ./nix/importer.nix) {
                   groups = [ "${builtins.head recommendedGroups}" ... ];
                }
            ''
          else
            ''
              Dependency '${ident}' was requested for evaluation but does not exist in any group.

              Currently enabled groups: ${enabledGroups}
              Available groups: ${builtins.toString (builtins.attrNames availableGroups)}

              To fix add '${ident}' to at least one group.

              NOTE: that 'eval' and 'dev' are the default groups to choose from.
            ''
        )
    ) lock;

  root =
    {
      groups ? [ "eval" ],
    }:
    let
      manifest = import ../mana.nix;
      scope = (
        importTree {
          inherit groups manifest;
          lock = builtins.fromJSON (builtins.readFile ../lock.json);
        }
      );
      f = import manifest.entrypoint;
    in
    f (builtins.intersectAttrs (builtins.functionArgs f) scope);
in
root
