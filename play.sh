#!/usr/bin/env bash
# 《缘之空》Godot 原生移植版启动脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="$(command -v godot 2>/dev/null || echo "/usr/local/bin/godot")"

if [ ! -x "$GODOT_BIN" ]; then
    echo "❌ 错误：未找到 Godot 可执行程序！"
    echo "请确认系统已安装 Godot 4 (>= 4.4) 并加入 PATH。"
    exit 1
fi

GAME_DIR="$SCRIPT_DIR/缘之空（全cg步兵版）"
PROJECT_DIR="$SCRIPT_DIR/godot_port"

if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    echo "🌸 《缘之空》Godot 原生移植版启动器"
    echo ""
    echo "用法:"
    echo "  ./play.sh                 启动到原版标题画面（默认推荐）"
    echo "  ./play.sh --game          直接进入开场序章剧情（车厢场景）"
    echo "  ./play.sh --scenario <名> 直接指定运行剧本（如 00_A020、00_Z005 等）"
    echo "  ./play.sh --inspector     打开归档资源与字节码检测器（Archive Inspector）"
    echo "  ./play.sh --editor        在 Godot 编辑器中打开本项目"
    echo ""
    exit 0
fi

if [ "$1" == "--editor" ]; then
    echo "🚀 正在打开 Godot 编辑器..."
    exec "$GODOT_BIN" -e --path "$PROJECT_DIR"
fi

if [ "$1" == "--inspector" ]; then
    echo "🔍 正在启动资源检测器 (Archive Inspector)..."
    exec "$GODOT_BIN" --path "$PROJECT_DIR" res://scenes/archive_inspector.tscn -- "$GAME_DIR"
fi

EXTRA_ARGS=()
HAS_TITLE=false
HAS_SCENARIO=false

for arg in "$@"; do
    if [ "$arg" == "--game" ]; then
        HAS_SCENARIO=true
    elif [ "$arg" == "--title" ]; then
        HAS_TITLE=true
        EXTRA_ARGS+=("$arg")
    elif [ "$arg" == "--scenario" ] || [[ "$arg" == --scenario=* ]]; then
        HAS_SCENARIO=true
        EXTRA_ARGS+=("$arg")
    else
        EXTRA_ARGS+=("$arg")
    fi
done

if [ "$HAS_SCENARIO" = false ] && [ "$HAS_TITLE" = false ]; then
    EXTRA_ARGS=("--title" "${EXTRA_ARGS[@]}")
fi

echo "========================================================"
echo "🌸 启动《缘之空》Godot 原生移植版"
echo "========================================================"
echo "游戏资源: $GAME_DIR (100% 原始未改动)"
echo "项目路径: $PROJECT_DIR"
echo "操作提示:"
echo "  • 推进剧情 / 确认: 鼠标左键 / Enter / 空格"
echo "  • 隐藏/显示对话框: 鼠标右键"
echo "  • 历史记录回顾: 鼠标滚轮向上 / PageUp / 点击底部「历史」"
echo "  • 呼出系统菜单 / 关闭弹窗: ESC"
echo "  • 底部快捷按钮: 快存、快读、存档、读档、设置、自动、快进"
echo "========================================================"

exec "$GODOT_BIN" --path "$PROJECT_DIR" res://scenes/adv_player.tscn -- "${EXTRA_ARGS[@]}" "$GAME_DIR"
