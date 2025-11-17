# Output shim for nix run compat
{
  outputs =
    _:
    let
      systems = [
        "aarch64-linux"
        "x86_64-linux"

        "x86_64-darwin"
        "aarch64-darwin"
      ];
    in
    {
      packages = builtins.listToAttrs (
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
        }) systems
      );
    };
}
