# 赛博修仙系统

一款把 AI Agent 工作流做成修仙成长体验的 Godot 黑客松作品：玩家在万象宗领取任务，通过“本命法器”ZCode 派发真实 Agent 会话，并在青芜原种植、探索和指挥九尾狐器灵战斗。

![项目封面](docs/项目封面.png)

## 下载已导出的 macOS App

不安装 Godot 也可以直接体验：[下载黑客松演示版 App（GitHub Release）](https://github.com/shinna782-hub/newbuilder/releases/tag/v1.0.0-hackathon)。下载 ZIP、完整解压后，右键点击“赛博修仙系统.app”并选择“打开”。

## 直接运行

1. 安装 [Godot 4.7](https://godotengine.org/) 或兼容的 Godot 4.x。
2. 用 Godot 导入仓库根目录的 `project.godot`。
3. 点击运行项目，或在仓库根目录执行：

```bash
godot --path .
```

macOS 可用 `/Applications/Godot.app/Contents/MacOS/Godot --path .`。

## 连接 ZCode 法宝桥（可选）

完整玩法需要 Node.js 22.5+ 和已登录的 ZCode 桌面端：

```bash
ZCODE_WORKSPACE="$PWD/演示沙盒" node 黑客松/法宝桥/bridge.js
```

随后在 ZCode 中选择“添加项目 / 打开文件夹”，添加本仓库的 `演示沙盒`。保持法宝桥终端运行，再在游戏任务列表点击“去修炼”。

## 验收

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -- --clicktest
```

自动验收覆盖三段开场 PV、进度跳过与重置、种植/收割、任务列表、地图连通性、器灵工具格以及两回合狐火战斗。

## 公开仓库范围

这里仅包含运行游戏所需的 Godot 工程、法宝桥和部署说明。原始音乐素材包、参考图、美术源文件、私有策划资料、Godot 导入缓存和已导出的 App 均未上传。

首次安装与完整游玩说明见 [docs/第一次安装与游玩指南.md](docs/第一次安装与游玩指南.md)。
