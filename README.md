# rshy
基于 Flakes 的模块化 Nix 配置框架

## 快速开始

```nix
# flake.nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.rshy.url = "github:anialic/rshy";
  
  outputs = { nixpkgs, rshy, ... }: rshy.mkFlake {
    inherit nixpkgs;
    src = ./.;
  };
}
```
```nix
# config.nix
{ lib, ... }:
{
  config.nodeOptions = [{
    options.base = {
      hostName = lib.mkOption { type = lib.types.str; };
      enableSSH = lib.mkEnableOption "Enable SSH server";
    };
  }];
  
  config.modules = [{
    target = "nixos";
    module = { node, ... }: {
      networking.hostName = node.base.hostName;
      system.stateVersion = "25.11";
      services.openssh.enable = node.base.enableSSH;
    };
  }];
  
  config.nodes.my-machine = {
    system = "x86_64-linux";
    base = { hostName = "my-machine"; enableSSH = true; };
    
    extraModules = [ ({ modulesPath, ... }: {
      imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];
      boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" ];
      fileSystems."/" = {
        device = "/dev/disk/by-uuid/...";
        fsType = "ext4";
      };
    }) ];
  };
}
```
```nix
# 请不要直接运行
sudo nixos-rebuild switch --flake .#my-machine
```

## `rshy.mkFlake` 参数

```nix
rshy.mkFlake {
  # 必需参数
  nixpkgs = ...;      # nixpkgs 输入
  src = ./.;         # 配置源目录
  
  # 可选参数
  home-manager = ...;   # 用于 target = "home" 的节点
  nix-darwin = ...;     # 用于 target = "darwin" 的节点
  
  # 参数传递
  args = { ... };       # 传递给框架模块的参数
  nodeArgs = { ... };   # 传递给节点模块的参数
  
  # 文件扫描
  exclude = name: ...;  # 文件/目录排除函数
}
```

### 详细

- `nixpkgs`: nixpkgs 输入，用于构建配置
- `src`: 配置源目录，框架会递归扫描其中的 .nix 文件
- `home-manager`: 当节点使用 target = "home" 时需要传入
- `nix-darwin`: 当节点使用 target = "darwin" 时需要传入
- `args`: 框架模块可用的参数，默认包含 `{ inherit nixpkgs lib; }`
- `nodeArgs`: 所有节点模块系统可用的参数，默认包含 `{ node name system }`
- `exclude`: 文件扫描排除规则，默认排除开头 `_` 或者 `.` 的目录或者文件，例如：

```nix
  exclude = name: 
  let c = builtins.substring 0 1 name;
  in c == "_" || c == "." || name == "flake.nix" || c == "@";
```

## 配置结构

`config.nodeOptions`

选项声明，定义配置的结构和类型：

```nix
config.nodeOptions = [{
  options.base = {
    hostName = lib.mkOption { type = lib.types.str; };
    enableDesktop = lib.mkOption { 
      type = lib.types.bool; 
      default = false; 
    };
  };
}];
```

`config.modules`

配置模块，每个模块包含：

- target: "nixos"、"darwin" 或 "home"
- module: 配置函数，接收 { node, pkgs, ... } 参数

```nix
config.modules = [{
  target = "nixos";
  module = { node, pkgs, ... }: {
    services.nginx.enable = lib.mkIf node.base.enableWebServer true;
  };
}];
```
`config.nodes.<name>`

节点定义，每个节点包含：

- `system`: 系统架构字符串（如 "x86_64-linux"）
- `target`: 可选，自动推断或显式指定（"nixos"、"darwin"、"home"）
- `extraModules`: 节点特定的额外模块列表
- `instantiate`: 可选，自定义构建函数
- 其他：选项值

```nix
config.nodes = {
  server = {
    system = "x86_64-linux";
    base.hostName = "server";
    extraModules = [{ services.nginx.enable = true; }];
  };
};
```

`config.flake`

自定义 Flake 输出：

```nix
config.flake = {
  formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt;
  devShells.x86_64-linux.default = /* ... */;
  packages.x86_64-linux.myapp = /* ... */;
  overlays.default = /* ... */;
};
```
`config.assertions`

断言列表，每个断言包含：

- assertion: 布尔表达式
- message: 失败时显示的消息

```nix
config.assertions = [{
  assertion = config.nodes != {};
  message = "至少需要一个节点";
}];
```

`config.systems`

它是一个系统结构列表，默认是 ["x86_64-linux", "aarch64-linux", "aarch64-darwin", "x86_64-darwin"]。

## 使用示例

### 多平台管理

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    rshy.url = "github:anialic/rshy";
  };
  
  outputs = { nixpkgs, home-manager, rshy, ... }:
    rshy.mkFlake {
      inherit nixpkgs home-manager;
      src = ./.;
    };
}
```
```nix
# config.nix
{ lib, ... }:
{
  config.nodeOptions = [{
    options.user = {
      name = lib.mkOption { type = lib.types.str; };
      enableDev = lib.mkOption { 
        type = lib.types.bool; 
        default = false; 
      };
    };
  }];
  
  config.modules = [
    {
      target = "nixos";
      module = { node, pkgs, ... }: {
        users.users.${node.user.name}.isNormalUser = true;
        environment.systemPackages = 
          lib.optionals node.user.enableDev [ pkgs.git pkgs.vim ];
      };
    }
    {
      target = "home";
      module = { node, pkgs, ... }: {
        home.username = node.user.name;
        home.packages = 
          lib.optionals node.user.enableDev [ pkgs.vscode ];
      };
    }
  ];
  
  config.nodes = {
    laptop = {
      system = "x86_64-linux";
      user = { name = "alice"; enableDev = true; };
    };
    
    home = {
      system = "x86_64-linux";
      target = "home";
      user = { name = "alice"; enableDev = true; };
    };
  };
}
```
```bash
# NixOS 系统
sudo nixos-rebuild switch --flake .#dev-laptop

# Home Manager
home-manager switch --flake .#home-config
```
### 单独修改一个节点的 nixpkgs 版本

```nix
config.nodes.bob = {
  system = "x86_64-linux";
  target = "nixos";
  # 用自定义的 instantiate ，指定使用 stable 的 nixpkgs
  instantiate = { system, modules }:
    inputs.nixpkgs-stable.lib.nixosSystem { inherit system modules; };
};
```

### 自定义 formatter

```nix
{
  config,
  nixpkgs,
  lib,
  ...
}:
let
  mkFormatter =
    system:
    let
      pkgs = nixpkgs.legacyPackages.${system};

      log =
        color: msg:
        let
          colors = {
            blue = "\\033[1;34m";
            green = "\\033[1;32m";
            reset = "\\033[0m";
          };
        in
        ''echo -e "${colors.${color}}▶${colors.reset} ${msg}"'';
    in
    pkgs.writeShellApplication {
      name = "fmt";
      runtimeInputs = with pkgs; [
        fd
        nixfmt-rfc-style
        deadnix
        statix
      ];
      text = ''
        set -euo pipefail

        ${log "blue" "Formatting *.nix files..."}
        fd -e nix -x nixfmt '{}'

        ${log "blue" "Checking dead code..."}
        fd -e nix -x deadnix --no-lambda-arg --no-lambda-pattern-names -e '{}'

        ${log "blue" "Running statix..."}
        fd -e nix -x statix fix '{}'

        ${log "green" "✨ All done!"}
      '';
    };
in
{
  # 为每个系统添加 formatter
  config.flake.formatter = lib.genAttrs config.systems mkFormatter;
}
```
### 断言

```nix
{ config, lib, ... }:
let
  nodes = config.nodes;
  invalidNetwork = lib.filterAttrs
    (_: n: 
      let
        network = n.network or {};
        iwd = network.iwd or false;
        networkd = network.networkd or false;
      in
      # 两者不同时为 true 且不同时为 false 时无效
      iwd != networkd
    )
    nodes;
in
{
  config.assertions = [
    {
      assertion = invalidNetwork == {};
      message = "network.iwd 和 network.networkd 必须同时开启或同时关闭，以下节点配置不一致: ${lib.concatStringsSep ", " (builtins.attrNames invalidNetwork)}";
    }
   ];
};
```
