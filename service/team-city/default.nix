{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.team-city;
  team-city = cfg.package;
  preStart = pkgs.writeShellScript "team-city-pre-start" ''
  # the server process write files relative to its bin so it needs to run from the state dir
  echo "symlinking bin/ contents"
  for i in $(ls ${team-city}/bin); do
    ln -sfn ${team-city}/bin/$i ${cfg.dataPath}/bin/`basename $i`
  done

  # conf needs to be writable so we create it and symlink everything from vendor
  echo "symlinking conf/ contents"
  for i in $(ls ${team-city}/conf); do
    ln -sfn ${team-city}/conf/$i ${cfg.dataPath}/conf/`basename $i`
  done

  # stage entire webapp in state dir. Team City wants WEB-INF to be writable and enabling symlinks for Tomcat seems a bit brute
  echo "staging webapps/ROOT/.."
  ${pkgs.rsync}/bin/rsync -au ${team-city}/webapps/ROOT ${cfg.dataPath}/webapps/
  chown -R ${cfg.user}:${cfg.group} ${cfg.dataPath}/webapps/ROOT
  chmod -R 750 ${cfg.dataPath}/webapps/ROOT
  '';
in
{
  options = {
    services.team-city = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to enable the Team City server.
        '';
      };

      user = lib.mkOption {
        default = "teamcity";
        type = lib.types.str;
        description = ''
          User the Team City server should execute under.
        '';
      };

      group = lib.mkOption {
        default = "teamcity";
        type = lib.types.str;
        description = ''
          If the default user "teamcity" is configured then this is the primary
          group of that user.
        '';
      };

      dataPath = lib.mkOption {
        default = "/var/lib/teamcity";
        type = lib.types.path;
        description = ''
          The path to use as TEAMCITY_DATA_PATH. If the default user "teamcity" is configured then
          this will also become the home of the "teamcity" user.
        '';
      };

      package = lib.mkPackageOption pkgs "team-city" { };
    };
  };

  config = lib.mkIf cfg.enable {
    environment = {};

    users.users = lib.mkIf (cfg.user == "teamcity") {
      teamcity = {
        home = cfg.dataPath;
        group = cfg.group;
        useDefaultShell = true;
        isSystemUser = true;
      };
    };
    
    users.groups = lib.mkIf (cfg.group == "teamcity") {
      teamcity = { };
    };

    systemd.tmpfiles.rules = [
      "d '${cfg.dataPath}/bin' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.dataPath}/conf' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.dataPath}/logs' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.dataPath}/temp' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.dataPath}/webapps' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.dataPath}/work' 0750 ${cfg.user} ${cfg.group} - -"

      "L+ ${cfg.dataPath}/lib - - - - ${team-city}/lib"
    ];

    systemd.services.team-city = {
      description = "Team City server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        TEAMCITY_DATA_PATH = cfg.dataPath;
        TEAMCITY_LOGS_PATH = (cfg.dataPath + "/logs");
        CATALINA_HOME = cfg.dataPath;
        CATALINA_BASE = cfg.dataPath;
      };

      path = [
        "/run/current-system/sw" # we need sh on path
        team-city
      ];

      serviceConfig = {
        User = cfg.user;
        StateDirectory = lib.mkIf (lib.hasPrefix "/var/lib/teamcity" cfg.dataPath) "teamcity";
        TimeoutStartSec = 600; # we stage much of Team City into /var/lib so first start takes time
        ExecStartPre = "+${preStart}"; # we need chmod and chown to set everything up so run preStart as root
        ExecStart = "${cfg.dataPath}/bin/teamcity-server.sh run";
      };
    };
  };
}