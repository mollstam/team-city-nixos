{
  stdenv,
  fetchurl,
  jdk21_headless,
  lib,
  makeWrapper,
  patchelf,
  runCommand,
}:

let
  # Java 21 (TeamCity 2026.1+ requires it) with the roots distrusted after the
  # eMudhra CA compromise (CVE-2026-91403, CVE-2026-114820) removed from cacerts.
  # The intermediates involved are issued by AAA Certificate Services, so they
  # lose trust along with it. Drop this once nixpkgs ships a JDK with both fixes.
  #
  # The JDK is copied rather than symlinked because the JVM resolves java.home
  # (and therefore lib/security/cacerts) from the real path of its binaries.
  distrusted = [
    "AAA Certificate Services"
    "emSign ECC Root CA - G3"
    "emSign Root CA - G1"
    "emSign Root CA - G2"
  ];
  ownerRegex = "^Owner: .*CN=(${lib.concatStringsSep "|" distrusted})(,|$)";
  jre = runCommand "${jdk21_headless.name}-distrusted" { nativeBuildInputs = [ patchelf ]; } ''
    mkdir -p $out/lib
    cp -a ${jdk21_headless}/lib/openjdk $out/lib/openjdk
    chmod -R u+w $out/lib/openjdk
    ln -s lib/openjdk/bin $out/bin

    # nixpkgs bakes the original JDK's lib dirs into every RPATH. Left alone, the copy
    # loads a second libjava.so from the original and the JVM fails at runtime with
    # "platform encoding not initialized", so point them at the copy instead.
    find $out/lib/openjdk -type f | while IFS= read -r f; do
      rpath=$(patchelf --print-rpath "$f" 2>/dev/null) || continue
      case "$rpath" in
        *${jdk21_headless}*)
          patchelf --set-rpath "$(echo "$rpath" | sed "s|${jdk21_headless}|$out|g")" "$f"
          ;;
      esac
    done
    leftover=$(find $out/lib/openjdk -type f | while IFS= read -r f; do
      rpath=$(patchelf --print-rpath "$f" 2>/dev/null) || continue
      case "$rpath" in *${jdk21_headless}*) echo "$f: $rpath" ;; esac
    done)
    if [ -n "$leftover" ]; then
      echo "RPATHs still pointing into the original JDK:" >&2
      echo "$leftover" >&2
      exit 1
    fi

    ks=$out/lib/openjdk/lib/security/cacerts
    chmod u+w $(dirname $ks) $ks
    keytool=${jdk21_headless}/bin/keytool

    $keytool -list -v -keystore $ks -storepass changeit |
      awk -v re='${ownerRegex}' '
        /^Alias name: / { alias = substr($0, 13) }
        $0 ~ re { print alias }
      ' |
      while IFS= read -r alias; do
        echo "removing '$alias' from cacerts"
        $keytool -delete -alias "$alias" -keystore $ks -storepass changeit
      done

    if $keytool -list -v -keystore $ks -storepass changeit | grep -E '${ownerRegex}'; then
      echo "distrusted roots still present in cacerts" >&2
      exit 1
    fi
  '';
in
stdenv.mkDerivation rec {
  pname = "team-city";
  version = "2026.2.2";

  src = fetchurl {
    url = "https://download.jetbrains.com/teamcity/TeamCity-${version}.tar.gz";
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

    wrapProgram $out/bin/teamcity-server.sh --set JAVA_HOME "${jre}"
    wrapProgram $out/bin/maintainDB.sh --set JAVA_HOME "${jre}"

    runHook postInstall
  '';

  # Exposed so consumers (e.g. a custom truststore) can use the same JDK as the server.
  passthru.jre = jre;

  meta = with lib; {
    description = "Powerful Continuous Integration and Continuous Delivery out of the box";
    homepage = "https://www.jetbrains.com/teamcity/";
    platforms = platforms.linux;
    mainProgram = "teamcity-server";
    license = lib.licenses.unfree;
  };
}
