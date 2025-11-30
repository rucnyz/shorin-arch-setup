#!/bin/bash

# ==============================================================================
# 00-utils.sh - The "UI Engine"
# ==============================================================================

# --- 1. 颜色与样式 ---
export NC='\033[0m'
export BOLD='\033[1m'
export DIM='\033[2m'
export ITALIC='\033[3m'

# 基础色
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export MAGENTA='\033[0;35m'
export CYAN='\033[0;36m'

# 高亮色 (TTY Friendly)
export H_RED='\033[1;31m'
export H_GREEN='\033[1;32m'
export H_YELLOW='\033[1;33m'
export H_BLUE='\033[1;34m'
export H_MAGENTA='\033[1;35m'
export H_CYAN='\033[1;36m'

# --- 2. 基础函数 ---

# 权限检查
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${H_RED}❌ Error: You must be root to run this script.${NC}"
        echo -e "${DIM}   Try running with sudo.${NC}"
        exit 1
    fi
}

# 获取时间戳
timestamp() {
    date "+%H:%M:%S"
}

# 动态分割线
hr() {
    printf "${DIM}%*s${NC}\n" "${COLUMNS:-$(tput cols)}" '' | tr ' ' '-'
}

# --- 3. 特效函数 ---

# 打字机效果 (Typewriter Effect)
# 用法: typer "Hello World" [速度]
typer() {
    text="$1"
    delay="${2:-0.01}"
    for (( i=0; i<${#text}; i++ )); do
        echo -n "${text:$i:1}"
        sleep $delay
    done
    echo ""
}

# 带有边框的标题
box_title() {
    local text=" $1 "
    local color="${2:-$H_CYAN}"
    local len=${#text}
    
    echo ""
    echo -e "${color}╔$(printf '═%.0s' $(seq 1 $len))╗${NC}"
    echo -e "${color}║${NC}${BOLD}${text}${NC}${color}║${NC}"
    echo -e "${color}╚$(printf '═%.0s' $(seq 1 $len))╝${NC}"
    echo ""
}

# --- 4. 日志函数 ---

log() {
    echo -e "${DIM}[$(timestamp)]${NC} ${H_BLUE}➜${NC} $1"
}

success() {
    echo -e "${DIM}[$(timestamp)]${NC} ${H_GREEN}✔${NC} ${BOLD}$1${NC}"
}

warn() {
    echo -e "${DIM}[$(timestamp)]${NC} ${H_YELLOW}⚡${NC} ${YELLOW}$1${NC}"
}

error() {
    echo -e "${DIM}[$(timestamp)]${NC} ${H_RED}✖${NC} ${H_RED}$1${NC}"
}

# 任务开始 (不换行，用于长时间任务)
task_start() {
    echo -ne "${DIM}[$(timestamp)]${NC} ${H_CYAN}⚙${NC} $1..."
}

# 任务结束
task_done() {
    echo -e " ${H_GREEN}Done.${NC}"
}

task_fail() {
    echo -e " ${H_RED}Failed!${NC}"
}