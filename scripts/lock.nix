{ cwd }:
let
  manifest = import (cwd + "/mana.nix");
  collectLockEntries =
    path: manifest:
    builtins.mapAttrs (
      ident: spec:
      let
        inherit (spec) url;
        fetchTreeArgs = (builtins.parseFlakeRef url) // (spec.args or { });
        fetchResult = fetchTree fetchTreeArgs;
        nestedManifestFile = "${fetchResult}/mana.nix";
        optManifestFile = if builtins.pathExists nestedManifestFile then import nestedManifestFile else { };
        dependencies = collectLockEntries (path + [ ident ]) optManifestFile;
      in
      {
        args = fetchTreeArgs;
        locked = removeAttrs fetchResult [ "outPath" ];
        inherit url dependencies;
      }
    ) (manifest.dependencies or { });
  result = collectLockEntries [] manifest;
in
result
