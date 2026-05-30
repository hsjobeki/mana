let
  fixturesDir = ../tests/fixtures;

  mockFetchTree =
    args:
    let
      key =
        if args ? owner && args ? repo then
          "${args.owner}/${args.repo}"
        else
          throw "mockFetchTree: unsupported args ${builtins.toJSON args}";
    in
    if mockSources ? ${key} then
      mockSources.${key}
    else
      throw "mockFetchTree: unknown '${key}'";

  mockSources = {
    "test/dep" = {
      outPath = "${fixturesDir}/dep-with-default";
      rev = "mock-rev";
      narHash = "sha256-mock";
    };
  };

  importWith =
    args: builtins.scopedImport { fetchTree = mockFetchTree; } ./importer.nix args;

  simpleLock = {
    sources.dep = {
      args = {
        type = "github";
        owner = "test";
        repo = "dep";
      };
      locked = {
        rev = "mock-rev";
        narHash = "sha256-mock";
      };
    };
    deps."" = {
      dep = "dep";
    };
  };
in
{
  # User claim: dependencies.dep.entrypoint = null should return raw source,
  # not import default.nix. Dep has no mana.nix.
  test_entrypoint-null-returns-raw-source =
    let
      result = importWith {
        manifest = {
          entrypoint = fixturesDir + "/passthrough-entrypoint.nix";
          dependencies.dep = {
            url = "github:test/dep";
            entrypoint = null;
          };
        };
        lock = simpleLock;
      };
    in
    {
      # entrypoint=null means raw source — the fetchTree result, not an imported value
      expr = result.dep.outPath;
      expected = "${fixturesDir}/dep-with-default";
    };
}
