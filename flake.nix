{
  description = "herdr-bob — run IBM Bob Shell as a first-class Herdr agent";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      overlays.default = final: prev: {
        herdr-bob = final.callPackage ./package.nix { };
      };

      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        rec {
          herdr-bob = pkgs.callPackage ./package.nix { };
          default = herdr-bob;
        }
      );

      # Registers the plugin with Herdr for the listed users, the same way the
      # rest of a NixOS-managed Herdr config does it.
      nixosModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.programs.herdr-bob;
        in
        {
          options.programs.herdr-bob = {
            enable = lib.mkEnableOption "the herdr-bob Herdr plugin";

            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.herdr-bob;
              defaultText = lib.literalExpression "herdr-bob.packages.\${system}.herdr-bob";
              description = "The herdr-bob package to install and register.";
            };

            herdrPackage = lib.mkOption {
              type = lib.types.package;
              default = pkgs.herdr;
              defaultText = lib.literalExpression "pkgs.herdr";
              description = ''
                The Herdr package whose `herdr` binary registers the plugin.
                Must be the same Herdr the user actually runs, since the plugin
                registry lives in that Herdr's config directory.
              '';
            };

            users = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              example = [ "alice" ];
              description = ''
                Users to register the plugin for. Herdr's plugin registry is
                per-user, so each one needs its own registration.
              '';
            };
          };

          config = lib.mkIf cfg.enable {
            environment.systemPackages = [ cfg.package ];

            warnings = lib.optional (cfg.users == [ ]) ''
              programs.herdr-bob.enable is on but programs.herdr-bob.users is
              empty, so the plugin is installed but registered for nobody.
            '';

            # Herdr's registry API rather than editing its files, so other
            # installed plugins stay intact. Linking also works offline, before
            # any Herdr server has started.
            systemd.services = lib.listToAttrs (
              map (
                user:
                lib.nameValuePair "herdr-bob-register-${user}" {
                  description = "Register the herdr-bob Herdr plugin for ${user}";
                  wantedBy = [ "multi-user.target" ];
                  after = [ "local-fs.target" ];
                  unitConfig.RequiresMountsFor = config.users.users.${user}.home;
                  environment.HOME = config.users.users.${user}.home;
                  serviceConfig = {
                    Type = "oneshot";
                    User = user;
                    RemainAfterExit = true;
                    ExecStart = "${lib.getExe cfg.herdrPackage} plugin link ${cfg.package}/share/herdr/plugins/herdr-bob";
                  };
                }
              ) cfg.users
            );
          };
        };

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
