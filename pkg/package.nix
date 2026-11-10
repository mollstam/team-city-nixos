{
  stdenv,
  fetchurl,
  jdk21_headless,
  lib,
  makeWrapper,
}:

stdenv.mkDerivation rec {
  pname = "team-city";
  version = "2026.2.2";

  src = fetchurl {
    url = "https://download-cdn.jetbrains.com/teamcity/TeamCity-${version}.tar.gz";
    sha256 = "sha256-Db2OcqN9JQmyyL1ziG3faZsswLn2mId+jScmUTJE6bQ=";
  };

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    mv * "$out"

    # remove some windows/mac scripts for purity
    # -f so a layout change in a new release doesn't break the build
    rm -f $out/bin/*.bat $out/bin/*.ps1 $out/bin/*.cmd $out/bin/*.exe
    rm -f $out/buildAgent/bin/*.bat $out/buildAgent/bin/*.exe $out/buildAgent/bin/*.plist*
    rm -f $out/buildAgent/bin/mac.launchd.sh

    wrapProgram $out/bin/teamcity-server.sh --set JAVA_HOME "${jdk21_headless}"
    wrapProgram $out/bin/maintainDB.sh --set JAVA_HOME "${jdk21_headless}"

    runHook postInstall
  '';

  # TeamCity 2026.1+ only runs on Java 21. Exposed so consumers (e.g. a custom
  # truststore) can use the same JDK as the server.
  passthru.jre = jdk21_headless;

  meta = with lib; {
    description = "Powerful Continuous Integration and Continuous Delivery out of the box";
    homepage = "https://www.jetbrains.com/teamcity/";
    platforms = platforms.linux;
    mainProgram = "teamcity-server";
    license = lib.licenses.unfree;
  };
}
