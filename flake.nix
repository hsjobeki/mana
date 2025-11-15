# Output shim for nix run compat
{
  outputs = _: {
    packages = builtins.builtins.listToAttrs (
      map (system: {
        name = system;
        value = import ./default.nix { inherit system; };
      }) [ "x86_64-linux" ]
    );
  };
}
