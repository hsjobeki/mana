# Output shim for nix run compat
{
  outputs = _: {
    packages = builtins.builtins.listToAttrs (
      map (system: {
        name = system;
        value =
          let
            self = import ./default.nix { inherit system; };
          in
          self
          // {
            default = self.mana;
          };
      }) [ "x86_64-linux" ]
    );
  };
}
