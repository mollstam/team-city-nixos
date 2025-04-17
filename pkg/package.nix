{
  stdenv,
  fetchurl,
  jre,
  lib,
  makeWrapper,
}:

stdenv.mkDerivation rec {
  pname = "team-city";
  version = "2025.03";

  src = fetchurl {
    url = "https://download-cdn.jetbrains.com/teamcity/TeamCity-${version}.tar.gz";
    sha256 = "sha256-0nQPrdVWuF9dXtPK8MWjnH+DCgBdRYQTFMc9xXEgxvc=";
  };

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    mv * "$out"

    # remove some windows/mac scripts for purity
    rm $out/bin/*.bat $out/bin/*.ps1 $out/bin/*.cmd $out/bin/*.exe
    rm $out/buildAgent/bin/*.bat $out/buildAgent/bin/*.exe $out/buildAgent/bin/*.plist*
    rm $out/buildAgent/bin/mac.launchd.sh

    wrapProgram $out/bin/teamcity-server.sh --set JAVA_HOME "${jre}"
    wrapProgram $out/bin/maintainDB.sh --set JAVA_HOME "${jre}"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Powerful Continuous Integration and Continuous Delivery out of the box";
    homepage = "https://www.jetbrains.com/teamcity/";
    platforms = platforms.linux;
    mainProgram = "teamcity-server";
    license = lib.licenses.unfree;
  };
}
