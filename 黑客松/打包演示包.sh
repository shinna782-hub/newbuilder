#!/bin/bash
#
# 把游戏打包成可以拷到另一台 Mac 直接跑的演示包。
#
#   bash 黑客松/打包演示包.sh
#
# 产出 赛博修仙-演示包/，整个目录拷过去即可。
# 演示机不需要装 Godot，但需要 Node ≥22.5 和已登录的 ZCode（见部署清单）。

set -e

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PROJ="$HERE/游戏原型-Godot"
OUT="$HERE/赛博修仙-演示包"

echo "==> 清理旧包"
rm -rf "$OUT"
mkdir -p "$OUT"

echo "==> 检查导出模板"
if [ ! -d "$HOME/Library/Application Support/Godot/export_templates/4.7.2.stable" ]; then
  echo "!! 没装导出模板，无法生成独立 .app"
  echo "   在 Godot 里：编辑器 → 管理导出模板 → 下载并安装"
  echo "   或者退而求其次：演示机装 Godot，直接拷 游戏原型-Godot/ 过去用编辑器跑"
  exit 1
fi

echo "==> 强制刷新 Godot 导入资源"
"$GODOT" --headless --path "$PROJ" --import

echo "==> 导出 macOS 应用（通用二进制）"
cd "$PROJ"
"$GODOT" --headless --path . --export-release "macOS" "$OUT/赛博修仙系统.app" 2>&1 \
  | grep -viE "^\[|loading_|^$" || true

if [ ! -d "$OUT/赛博修仙系统.app" ]; then
  echo "!! 导出失败，没生成 .app"
  exit 1
fi

echo "==> 拷法宝桥"
mkdir -p "$OUT/法宝桥"
cp "$HERE/黑客松/法宝桥/bridge.js" "$OUT/法宝桥/"

echo "==> 建空沙盒"
mkdir -p "$OUT/演示沙盒"
cat > "$OUT/演示沙盒/.gitkeep" <<'EOF'
这个目录是 Agent 干活的地方，演示前应该是空的。
EOF

echo "==> 写启动脚本"
cat > "$OUT/启动.command" <<'LAUNCHER'
#!/bin/bash
# 双击我：先起法宝桥，再起游戏。
cd "$(dirname "$0")"
ROOT="$(pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "没找到 node。去 https://nodejs.org 装一个 LTS（要 22.5 以上）"
  read -p "回车退出"; exit 1
fi

NODE_MAJOR=$(node -p "process.versions.node.split('.')[0]")
NODE_MINOR=$(node -p "process.versions.node.split('.')[1]")
if [ "$NODE_MAJOR" -lt 22 ] || { [ "$NODE_MAJOR" -eq 22 ] && [ "$NODE_MINOR" -lt 5 ]; }; then
  echo "Node 版本太低（$(node -v)），法宝桥用的 node:sqlite 需要 22.5 以上。"
  read -p "回车退出"; exit 1
fi

# 终端代理会把发往 127.0.0.1 的请求也劫走，这里显式绕开
export NO_PROXY="*"
export no_proxy="*"

echo "启动法宝桥…"
ZCODE_WORKSPACE="$ROOT/演示沙盒" node "$ROOT/法宝桥/bridge.js" &
BRIDGE_PID=$!
sleep 2

if ! curl --noproxy '*' -s --max-time 4 http://127.0.0.1:7777/health >/dev/null; then
  echo "!! 桥没起来。先单独跑一次看报什么错："
  echo "   node \"$ROOT/法宝桥/bridge.js\""
  read -p "回车退出"; kill $BRIDGE_PID 2>/dev/null; exit 1
fi
echo "法宝桥已通。"

echo "让 ZCode 打开本次演示使用的游戏沙盒…"
open -a "ZCode" "$ROOT/演示沙盒" 2>/dev/null || true
echo "如果 ZCode 项目列表里还没有这个目录，请手动选择「添加项目 / 打开文件夹」："
echo "  $ROOT/演示沙盒"

open "$ROOT/赛博修仙系统.app"
echo ""
echo "游戏已启动。这个窗口别关 —— 关了桥就断了。"
echo "演示结束后按 Ctrl+C 退出。"
wait $BRIDGE_PID
LAUNCHER
chmod +x "$OUT/启动.command"

cp "$HERE/黑客松/演示机部署清单.md" "$OUT/部署清单.md"
cp "$HERE/黑客松/第一次安装与游玩指南.md" "$OUT/第一次安装与游玩指南.md"

echo ""
echo "==> 打包完成：$OUT"
du -sh "$OUT"
echo ""
echo "整个目录拷到演示机，按 部署清单.md 走一遍。"
