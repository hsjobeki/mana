{
  cwd,
  updates ? { },
}:
let
  inherit (import ../nix/lib.nix)
    resolve
    getDependencyManifest
    ;

  rootManifest = import (cwd + "/mana.nix");
  currentLock = builtins.fromJSON (builtins.readFile (cwd + "/lock.json"));

  result = resolve {
    inherit getDependencyManifest currentLock updates;
    inherit (builtins) fetchTree;
  } rootManifest;

  # Pretty print json
  # cannot use 'jq' because this project doesn't use nixpkgs
  prettyJSON =
    indent: value:
    let
      spaces = builtins.concatStringsSep "" (builtins.genList (_: "  ") indent);
      nextSpaces = spaces + "  ";
    in
    if builtins.isAttrs value then
      "{\n"
      + builtins.concatStringsSep ",\n" (
        map (k: "${nextSpaces}\"${k}\": ${prettyJSON (indent + 1) value.${k}}") (builtins.attrNames value)
      )
      + "\n${spaces}}"
    else if builtins.isList value then
      "[\n"
      + builtins.concatStringsSep ",\n" (map (v: "${nextSpaces}${prettyJSON (indent + 1) v}") value)
      + "\n${spaces}]"
    else
      builtins.toJSON value;

  # prettyJSON 0 result
in
{
  result = prettyJSON 0 result;
}
