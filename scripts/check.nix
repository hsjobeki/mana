{
  cwd ? throw "pass either 'cwd' or 'rootManifest'",
  rootManifest ? import (cwd + "/mana.nix"),
}:
let
  inherit (builtins)
    isAttrs
    isList
    isString
    isPath
    removeAttrs
    attrNames
    filter
    length
    concatStringsSep
    concatMap
    match
    all
    trace
    ;

  check = pass: msg: { inherit pass msg; level = "error"; };
  warn = cond: msg: { pass = !cond; inherit msg; level = "warning"; };

  quote = ls: concatStringsSep ", " (map (s: "'" + toString s + "'") ls);

  extra = attrs: allowed: removeAttrs attrs allowed;

  rootAllowed = [
    "name"
    "description"
    "entrypoint"
    "dependencies"
    "groups"
    "shares"
    "pins"
  ];
  rootExtra = extra rootManifest rootAllowed;

  rootChecks = [
    (check (rootManifest ? entrypoint) "'entrypoint' is required")
    (check (rootExtra == { }) "Superfluous root attribute(s): ${quote (attrNames rootExtra)}")
    (check
      (!(rootManifest ? entrypoint) || isPath rootManifest.entrypoint)
      "'entrypoint' must be a path"
    )
    (check
      (!(rootManifest ? name) || isString rootManifest.name)
      "'name' must be a string"
    )
    (check
      (!(rootManifest ? description) || isString rootManifest.description)
      "'description' must be a string"
    )
    (check
      (!(rootManifest ? dependencies) || isAttrs rootManifest.dependencies)
      "'dependencies' must be an attribute set"
    )
    (check
      (!(rootManifest ? shares) || isList rootManifest.shares)
      "'shares' must be a list"
    )
    (check
      (!(rootManifest ? shares) || !(isList rootManifest.shares) || all isString rootManifest.shares)
      "'shares' entries must be strings"
    )
    (check
      (!(rootManifest ? pins) || isList rootManifest.pins)
      "'pins' must be a list"
    )
    (check
      (!(rootManifest ? pins) || !(isList rootManifest.pins) || all isString rootManifest.pins)
      "'pins' entries must be strings"
    )
    (check
      (!(rootManifest ? groups) || isAttrs rootManifest.groups)
      "'groups' must be an attribute set"
    )
  ];

  groupsChecks =
    if (rootManifest ? groups) && isAttrs rootManifest.groups then
      concatMap (
        groupName:
        let
          group = rootManifest.groups.${groupName};
        in
        [ (check (isAttrs group) "groups.${groupName}: must be an attribute set") ]
        ++ (
          if isAttrs group then
            map (
              depName: check (isList group.${depName}) "groups.${groupName}.${depName}: must be a list"
            ) (attrNames group)
          else
            [ ]
        )
      ) (attrNames rootManifest.groups)
    else
      [ ];


  depAllowed = [
    "url"
    "overrides"
    "pins"
    "entrypoint"
    "args"
  ];

  depChecks =
    if (rootManifest ? dependencies) && isAttrs rootManifest.dependencies then
      concatMap (
        name:
        let
          dep = rootManifest.dependencies.${name};
        in
        [
          (check (match ".*/.*" name == null) "dependencies.${name}: '/' is not allowed in dependency names")
          (check (isAttrs dep) "dependencies.${name}: must be an attribute set")
        ]
        ++ (
          if isAttrs dep then
            let
              depExtra = extra dep depAllowed;
            in
            [
              (check (dep ? url) "dependencies.${name}: 'url' is required")
              (check (depExtra == { }) "dependencies.${name}: superfluous attribute(s): ${quote (attrNames depExtra)}")
              (warn (dep ? overrides)
                "dependencies.${name}: 'overrides' is deprecated and has no effect"
              )
              (check
                (!(dep ? pins) || isList dep.pins)
                "dependencies.${name}: 'pins' must be a list"
              )
              (check
                (!(dep ? args) || isAttrs dep.args)
                "dependencies.${name}: 'args' must be an attribute set"
              )
              (check
                (!(dep ? entrypoint) || dep.entrypoint == null || isString dep.entrypoint)
                "dependencies.${name}: 'entrypoint' must be a string or null"
              )
            ]
          else
            [ ]
        )
      ) (attrNames rootManifest.dependencies)
    else
      [ ];

  # Report
  allChecks = rootChecks ++ groupsChecks ++ depChecks;
  errors = filter (c: !c.pass && c.level == "error") allChecks;
  warnings = filter (c: !c.pass && c.level == "warning") allChecks;

  printWarnings =
    if length warnings > 0 then
      trace (
        "mana.nix warnings:\n" + concatStringsSep "\n" (map (c: "  - ${c.msg}") warnings)
      )
    else
      x: x;
in
printWarnings (
  if length errors > 0 then
    throw (
      "mana.nix validation failed:\n" + concatStringsSep "\n" (map (c: "  - ${c.msg}") errors)
    )
  else
    true
)
