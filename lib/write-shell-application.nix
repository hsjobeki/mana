{
  mkdir,
  chmod,
  system,
}:
/**
  Custom 'writeShellApplication' based on builtins.derivation and pure posix sh
*/
{
  name,
  text,
}:
builtins.derivation {
  inherit name system;
  builder = "/bin/sh";
  scriptText = text;
  args = [
    "-c"
    ''
      ${mkdir} -p $out/bin

      printf '%s\n' "#!/usr/bin/env bash" > $out/bin/${name}
      printf '%s' "$scriptText" >> $out/bin/${name}

      ${chmod} +x $out/bin/${name}
    ''
  ];
}
