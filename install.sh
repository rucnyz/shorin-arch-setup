#!/bin/bash

# ==============================================================================
# Shorin Arch Setup - Main Installer (Visual Upgrade)
# ==============================================================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$BASE_DIR/scripts"
STATE_FILE="$BASE_DIR/.install_progress"

source "$SCRIPTS_DIR/00-utils.sh"

check_root
chmod +x "$SCRIPTS_DIR"/*.sh

# --- 随机 ASCII Banner ---
# 定义几个不同的 Banner 风格
banner1() {
cat << "EOF"
   _____ __  ______  ____  _____   __
  / ___// / / / __ \/ __ \/  _/ | / /
  \__ \/ /_/ / / / / /_/ // //  |/ / 
 ___/ / __  / /_/ / _, _// // /|  /  
/____/_/ /_/\____/_/ |_/___/_/ |_/   
EOF
}

banner2() {
cat << "EOF"
  ██████  ██   ██  ██████  ██████  ██ ███    ██ 
  ██      ██   ██ ██    ██ ██   ██ ██ ████   ██ 
  ███████ ███████ ██    ██ ██████  ██ ██ ██  ██ 
       ██ ██   ██ ██    ██ ██   ██ ██ ██  ██ ██ 
  ██████  ██   ██  ██████  ██   ██ ██ ██   ████ 
EOF
}

banner3() {
cat << "EOF"
   ______ __ __  ____  ____   ____  ____  
  / ___/|  |  |/    ||    \ |    ||    \ 
 (   \_ |  |  |  o  ||  D  ) |  | |  _  |
  \__  ||  _  |     ||    /  |  | |  |  |
  /  \ ||  |  |  _  ||    \  |  | |  |  |
  \    ||  |  |  |  ||  .  \ |  | |  |  |
   \___||__|__|__|__||__|\_||____||__|__|
EOF
}

# 随机选择一个 Banner
show_banner() {
    clear
    local r=$(( $RANDOM % 3 ))
    echo -e "${H_CYAN}"
    case $r in
        0) banner1 ;;
        1) banner2 ;;
        2) banner3 ;;
    esac
    echo -e "${NC}"
    echo -e "${DIM}   :: Arch Linux Automation Protocol :: v2.0 ::${NC}"
    echo ""
}

# --- 系统信息面板 ---
sys_info() {
    echo -e "${H_BLUE}╔════ SYSTEM DIAGNOSTICS ══════════════════════════════╗${NC}"
    echo -e "${H_BLUE}║${NC} Kernel:  $(uname -r)"
    echo -e "${H_BLUE}║${NC} User:    $(whoami)"
    echo -e "${H_BLUE}║${NC} Memory:  $(free -h | awk '/^Mem/ {print $3 "/" $2}')"
    echo -e "${H_BLUE}║${NC} Disk:    $(df -h / | awk 'NR==2 {print $5 " used"}')"
    echo -e "${H_BLUE}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# --- 开始执行 ---

show_banner

# 打字机特效欢迎语
typer ">>> Initializing installation sequence..." 0.02
typer ">>> Loading modules..." 0.02
sleep 0.5
sys_info

# 模块列表
MODULES=(
    "01-base.sh"
    "02-musthave.sh"
    "03-user.sh"
    "04-niri-setup.sh"
    "05-apps.sh"
)

# 初始化状态文件
if [ ! -f "$STATE_FILE" ]; then
    touch "$STATE_FILE"
fi

# 进度计数
TOTAL_STEPS=${#MODULES[@]}
CURRENT_STEP=0

for module in "${MODULES[@]}"; do
    CURRENT_STEP=$((CURRENT_STEP + 1))
    script_path="$SCRIPTS_DIR/$module"
    
    if [ ! -f "$script_path" ]; then
        warn "Module not found: $module"
        continue
    fi

    # 绘制模块标题
    box_title "Module ${CURRENT_STEP}/${TOTAL_STEPS}: $module" "${H_MAGENTA}"

    # 检查断点
    if grep -q "^${module}$" "$STATE_FILE"; then
        echo -e "${H_GREEN}✔${NC} Module marked as COMPLETED."
        read -p "$(echo -e ${H_YELLOW}"  Skip this module? [Y/n] "${NC})" skip_choice
        skip_choice=${skip_choice:-Y}
        
        if [[ "$skip_choice" =~ ^[Yy]$ ]]; then
            log "Skipping $module..."
            continue
        else
            log "Force re-running $module..."
            sed -i "/^${module}$/d" "$STATE_FILE"
        fi
    fi

    # 执行模块
    # 使用 bash 执行，错误处理交由模块内部或返回值
    bash "$script_path"
    exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo "$module" >> "$STATE_FILE"
    else
        echo ""
        hr
        error "CRITICAL FAILURE IN MODULE: $module (Exit Code: $exit_code)"
        echo -e "${DIM}The installation sequence has been aborted.${NC}"
        echo -e "${DIM}Fix the issue and re-run ./install.sh to resume.${NC}"
        hr
        exit 1
    fi
done

# --- 结束画面 ---

clear
show_banner
box_title "INSTALLATION COMPLETE" "${H_GREEN}"

echo -e "   ${BOLD}Congratulations, Shorin!${NC}"
echo -e "   Your Arch Linux system has been successfully deployed."
echo ""
echo -e "   ${H_CYAN}➜${NC} Environment:  ${BOLD}Niri (Wayland)${NC}"
echo -e "   ${H_CYAN}➜${NC} Shell:        ${BOLD}Fish${NC}"
echo -e "   ${H_CYAN}➜${NC} AUR Helper:   ${BOLD}Yay${NC}"
echo ""
hr

# 清理
if [ -f "$STATE_FILE" ]; then
    rm "$STATE_FILE"
fi

echo -e "${H_YELLOW}>>> System requires a REBOOT to initialize new services.${NC}"

# 倒计时效果
for i in {10..1}; do
    echo -ne "\r${DIM}Auto-rebooting in ${i} seconds... (Press 'n' to cancel)${NC}"
    read -t 1 -N 1 input
    if [[ "$input" == "n" || "$input" == "N" ]]; then
        echo -e "\n${H_BLUE}>>> Reboot cancelled.${NC}"
        echo -e "Type ${BOLD}reboot${NC} when you are ready."
        exit 0
    fi
done

echo -e "\n${H_GREEN}>>> Rebooting now... See you on the other side!${NC}"
reboot