/**
  For nix run/install it two things are required to do:
  - mkdir $out/bin
  - chmod +x

  They are not possible with pure posix shell
  nixpkgs busybox only contains "mkdir"
  Use these hosted static binaries like a buffet
*/
let
  hashes = {
    x86_64-linux = {
      mkdir = "sha256-xh37D98GVuMwSgYWOo/m9G1IzoOkVNhM3/GxlMSCmfg=";
      chmod = "sha256-C6wGp45hDoedaVqtw0Iky+tzH3r4WmKFqVbhee5Ts3M=";
    };
    aarch64-linux = {
      mkdir = "sha256-iLrSIseshmOA0xRTeNN5WOVpe2A0Y/0EIzGWs/vUWLA=";
      chmod = "sha256-wI/e3VZ8PxCjRMcbeKWlZeVOrwZMtXVZurJwyDgnCPs=";
    };
    x86_64-darwin = {
      mkdir = "sha256-P/Sbh21DlM+5yz6PfGiMld3dYh0OW/0CaMLiUvYFlfE=";
      chmod = "sha256-FCHqyJ8Zfo6EUT+PVli+Vk+BBiBzxteJ2kreYaqht80=";
    };
    aarch64-darwin = {
      mkdir = "sha256-1u/veSic0YT8AgTMTIN5QDbB44kQHe5qRAnszX8kmXY=";
      chmod = "sha256-OaA9k521+gJn1xLTmU3YuqePp13O8g0bptxZnAogUVM=";
    };
  };
in
builtins.mapAttrs (
  system: bins:
  builtins.mapAttrs (
    name: hash:
    import <nix/fetchurl.nix> {
      url = "https://github.com/pinpox/nix-toybox-static/releases/download/build-8/${name}-${system}";
      inherit hash;
      executable = true;
    }
  ) bins
) hashes
