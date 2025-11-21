{
  cwd,
  updates ? { },
}:
let
  inherit (import ../nix/lib.nix)
    normalizeManifest
    fetchLockEntries'
    ;

  rootManifest = import (cwd + "/mana.nix");
  currentLock = builtins.fromJSON (builtins.readFile (cwd + "/lock.json"));

  fetchLockEntries = fetchLockEntries' {
    inherit (builtins) fetchTree;
    inherit
      getDependencyManifest
      updates
      ;
    self = fetchLockEntries;
  };

  getDependencyManifest =
    source:
    let
      # This is not IFD, because source is from fetchTree
      # It should have the same performance impact however
      nestedManifestFile = "${source}/mana.nix";
      optManifestFile = if builtins.pathExists nestedManifestFile then import nestedManifestFile else { };

      nestedManifest = normalizeManifest { } optManifestFile;
    in
    nestedManifest;

  result = fetchLockEntries {
    path = [ ];
    lock = currentLock;
    transitiveOverrides = { };
    # Allow local overrides to propagate
    transitiveOverrideMode = "lenient"; # localOverrides > transitiveOverrides
  } (normalizeManifest { } rootManifest);

in
{
  inherit result;
}
