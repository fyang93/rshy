{
  nixpkgs ? throw "rshy: 'nixpkgs' is required",
  home-manager ? null,
  nix-darwin ? null,
  src ? throw "rshy: 'src' is required",
  args ? { },
  nodeArgs ? { },
  exclude ?
    name:
    let
      c = builtins.substring 0 1 name;
    in
    c == "_" || c == "." || name == "flake.nix",
}:
let
  inherit (nixpkgs) lib;
  scan =
    dir:
    let
      entries = builtins.readDir dir;
    in
    lib.concatMap (
      name:
      let
        path = dir + "/${name}";
        type = entries.${name};
      in
      if exclude name then
        [ ]
      else if type == "directory" then
        scan path
      else if type == "regular" && lib.hasSuffix ".nix" name then
        [ path ]
      else
        [ ]
    ) (builtins.attrNames entries);
  inferTarget = system: if lib.hasSuffix "-darwin" system then "darwin" else "nixos";
  getInstantiate =
    name: target:
    if target == "nixos" then
      {
        system,
        modules,
        moduleArgs,
      }:
      lib.nixosSystem {
        inherit system modules;
        specialArgs = moduleArgs;
      }
    else if target == "darwin" then
      if nix-darwin ? lib.darwinSystem then
        {
          system,
          modules,
          moduleArgs,
        }:
        nix-darwin.lib.darwinSystem {
          inherit system modules;
          specialArgs = moduleArgs;
        }
      else
        throw "rshy: node '${name}' (target=darwin) requires nix-darwin input"
    else if target == "home" then
      if home-manager ? lib.homeManagerConfiguration then
        {
          system,
          modules,
          moduleArgs,
        }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          inherit modules;
          extraSpecialArgs = moduleArgs;
        }
      else
        throw "rshy: node '${name}' (target=home) requires home-manager input"
    else
      throw "rshy: node '${name}' has invalid target '${target}'";
  coreModule =
    { config, ... }:
    let
      getTarget = node: if node.target != null then node.target else inferTarget node.system;
      filterNulls =
        attrs:
        lib.filterAttrs (_: v: v != null) (
          lib.mapAttrs (_: v: if builtins.isAttrs v && !(lib.isDerivation v) then filterNulls v else v) attrs
        );
      cleanNode =
        node:
        filterNulls (
          removeAttrs node [
            "system"
            "target"
            "extraModules"
            "instantiate"
          ]
        );
      nodesByTarget =
        let
          names = builtins.attrNames config.nodes;
        in
        builtins.groupBy (n: getTarget config.nodes.${n}) names;
      mkNode =
        name:
        let
          node = config.nodes.${name};
          target = getTarget node;
          instantiate = if node.instantiate != null then node.instantiate else getInstantiate name target;
          moduleArgs = {
            inherit name;
            inherit (node) system;
            node = cleanNode node;
          }
          // nodeArgs;
          targetModules = map (m: m.module) (builtins.filter (m: m.target == target) config.modules);
        in
        instantiate {
          inherit (node) system;
          inherit moduleArgs;
          modules = targetModules ++ (node.extraModules or [ ]);
        };
      mkConfigs =
        target:
        let
          names = nodesByTarget.${target} or [ ];
        in
        if names == [ ] then { } else lib.genAttrs names mkNode;
    in
    {
      options = {
        systems = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "x86_64-linux"
            "aarch64-linux"
            "aarch64-darwin"
            "x86_64-darwin"
          ];
        };
        nodeOptions = lib.mkOption {
          type = lib.types.listOf lib.types.deferredModule;
          default = [ ];
        };
        modules = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                target = lib.mkOption {
                  type = lib.types.enum [
                    "nixos"
                    "darwin"
                    "home"
                  ];
                };
                module = lib.mkOption { type = lib.types.raw; };
              };
            }
          );
          default = [ ];
        };
        nodes = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submoduleWith {
              modules = [
                {
                  options = {
                    system = lib.mkOption { type = lib.types.str; };
                    target = lib.mkOption {
                      type = lib.types.nullOr (
                        lib.types.enum [
                          "nixos"
                          "darwin"
                          "home"
                        ]
                      );
                      default = null;
                    };
                    extraModules = lib.mkOption {
                      type = lib.types.listOf lib.types.raw;
                      default = [ ];
                    };
                    instantiate = lib.mkOption {
                      type = lib.types.nullOr lib.types.raw;
                      default = null;
                    };
                  };
                }
              ]
              ++ config.nodeOptions;
            }
          );
          default = { };
        };
        assertions = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                assertion = lib.mkOption { type = lib.types.bool; };
                message = lib.mkOption { type = lib.types.str; };
              };
            }
          );
          default = [ ];
        };
        flake = lib.mkOption {
          type = lib.types.submoduleWith {
            modules = [
              {
                options = {
                  nixosConfigurations = lib.mkOption {
                    type = lib.types.attrsOf lib.types.raw;
                    default = { };
                  };
                  darwinConfigurations = lib.mkOption {
                    type = lib.types.attrsOf lib.types.raw;
                    default = { };
                  };
                  homeConfigurations = lib.mkOption {
                    type = lib.types.attrsOf lib.types.raw;
                    default = { };
                  };
                  formatter = lib.mkOption {
                    type = lib.types.attrsOf lib.types.package;
                    default = { };
                  };
                  packages = lib.mkOption {
                    type = lib.types.attrsOf (lib.types.attrsOf lib.types.package);
                    default = { };
                  };
                  devShells = lib.mkOption {
                    type = lib.types.attrsOf (lib.types.attrsOf lib.types.package);
                    default = { };
                  };
                  overlays = lib.mkOption {
                    type = lib.types.attrsOf lib.types.raw;
                    default = { };
                  };
                };
              }
            ];
          };
          default = { };
        };
      };
      config = {
        flake = {
          nixosConfigurations = lib.mkDefault (mkConfigs "nixos");
          darwinConfigurations = lib.mkDefault (mkConfigs "darwin");
          homeConfigurations = lib.mkDefault (mkConfigs "home");
          formatter = lib.mkDefault (
            lib.filterAttrs (_: v: v != null) (
              lib.genAttrs config.systems (s: nixpkgs.legacyPackages.${s}.nixfmt-rfc-style or null)
            )
          );
        };
        _module.args = {
          inherit nixpkgs lib;
        }
        // args;
      };
    };
  evaluated = lib.evalModules {
    modules = map import (scan src) ++ [ coreModule ];
  };
  failedAssertions = builtins.filter (a: !a.assertion) evaluated.config.assertions;
in
assert
  failedAssertions == [ ]
  || throw (
    "rshy: assertions failed\n" + lib.concatMapStringsSep "\n" (a: "  ✗ ${a.message}") failedAssertions
  );
lib.filterAttrs (_: v: v != { }) evaluated.config.flake
