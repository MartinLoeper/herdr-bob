{
  lib,
  stdenvNoCC,
  bash,
  coreutils,
  gnugrep,
  jq,
  util-linux,
}:

let
  # Everything the scripts shell out to. `herdr` itself is not here: Herdr
  # injects HERDR_BIN_PATH into plugin commands and into every managed pane, so
  # the binary that reports state is always the one actually running the session.
  # `bob` is not here either -- it is proprietary and installed separately.
  runtimePath = lib.makeBinPath [
    bash
    coreutils
    gnugrep
    jq
    util-linux # setsid
  ];
in
stdenvNoCC.mkDerivation {
  pname = "herdr-bob";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./bin
      ./lib
      ./herdr-plugin.toml
      ./rules.json
      ./README.md
      ./LICENSE
    ];
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    dir=$out/share/herdr/plugins/herdr-bob
    mkdir -p "$dir"
    cp -r bin lib herdr-plugin.toml rules.json README.md LICENSE "$dir/"
    chmod +x "$dir"/bin/*

    # One sourced file carries the closure, so every script picks it up.
    substituteInPlace "$dir/lib/common.sh" \
      --replace-fail '@runtimePath@' '${runtimePath}' \
      --replace-fail '@bash@' '${lib.getExe bash}'

    # Herdr does not run manifest commands through a shell, so `bash` would have
    # to be resolved from the caller's PATH. Pin it to the closure instead.
    substituteInPlace "$dir/herdr-plugin.toml" \
      --replace-fail '["bash", ' '["${lib.getExe bash}", '

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    dir=$out/share/herdr/plugins/herdr-bob
    for f in "$dir"/bin/* "$dir"/lib/common.sh; do
      ${lib.getExe bash} -n "$f"
    done
    ${lib.getExe jq} -e . "$dir/rules.json" > /dev/null
    # A leftover placeholder means the plugin would silently fall back to the
    # ambient PATH, which is exactly what packaging is meant to avoid.
    if ${lib.getExe gnugrep} -q '@runtimePath@\|@bash@' "$dir/lib/common.sh"; then
      echo "herdr-bob: unsubstituted placeholder left in common.sh" >&2
      exit 1
    fi
    if ${lib.getExe gnugrep} -q '"bash"' "$dir/herdr-plugin.toml"; then
      echo "herdr-bob: manifest still refers to an unpinned bash" >&2
      exit 1
    fi
  '';

  meta = {
    description = "Herdr plugin that runs IBM Bob Shell as a first-class agent";
    homepage = "https://github.com/MartinLoeper/herdr-bob";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
