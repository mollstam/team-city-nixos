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
    ln -sfn ${team-city}/bin/$i ${cfg.statePath}/bin/`basename $i`
  done

  # conf needs to be writable so we create it and symlink everything from vendor
  echo "symlinking conf/ contents"
  for i in $(ls ${team-city}/conf); do
    ln -sfn ${team-city}/conf/$i ${cfg.statePath}/conf/`basename $i`
  done

  # the server process wants to create some stuff in lib (jdbc drivers)
  echo "symlinking lib/ contents"
  for i in $(ls ${team-city}/lib); do
    ln -sfn ${team-city}/lib/$i ${cfg.statePath}/lib/`basename $i`
  done

  # stage entire webapp in state dir. Team City wants WEB-INF to be writable and enabling symlinks for Tomcat seems a bit brute
  echo "staging webapps/ROOT/.."
  ${pkgs.rsync}/bin/rsync -au ${team-city}/webapps/ROOT ${cfg.statePath}/webapps/
  chown -R ${cfg.user}:${cfg.group} ${cfg.statePath}/webapps/ROOT
  chmod -R 750 ${cfg.statePath}/webapps/ROOT
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

      statePath = lib.mkOption {
        default = "/var/lib/teamcity";
        type = lib.types.path;
        description = ''
          The path to use for state. TEAMCITY_DATA_PATH will be statePath + /data.
          If the default user "teamcity" is configured then this will also become the home of the "teamcity" user.
        '';
      };

      package = lib.mkPackageOption pkgs "team-city" { };
    };
  };

  config = lib.mkIf cfg.enable {
    environment = {};

    users.users = lib.mkIf (cfg.user == "teamcity") {
      teamcity = {
        home = cfg.statePath;
        group = cfg.group;
        useDefaultShell = true;
        isSystemUser = true;
      };
    };
    
    users.groups = lib.mkIf (cfg.group == "teamcity") {
      teamcity = { };
    };

    systemd.tmpfiles.rules = [
      "d '${cfg.statePath}/bin' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.statePath}/conf' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.statePath}/data' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.statePath}/lib' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.statePath}/logs' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.statePath}/temp' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.statePath}/webapps' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.statePath}/work' 0750 ${cfg.user} ${cfg.group} - -"
    ];

    systemd.services.team-city = {
      description = "Team City server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        TEAMCITY_DATA_PATH = (cfg.statePath + "/data");
        TEAMCITY_LOGS_PATH = (cfg.statePath + "/logs");
        CATALINA_HOME = cfg.statePath;
        CATALINA_BASE = cfg.statePath;
      };

      path = [
        "/run/current-system/sw" # we need sh on path
        team-city
      ];

      serviceConfig = {
        User = cfg.user;
        StateDirectory = lib.mkIf (lib.hasPrefix "/var/lib/teamcity" cfg.statePath) "teamcity";
        TimeoutStartSec = 600; # we stage much of Team City into /var/lib so first start takes time
        ExecStartPre = "+${preStart}"; # we need chmod and chown to set everything up so run preStart as root
        ExecStart = "${cfg.statePath}/bin/teamcity-server.sh run";
      };
    };
  };
}