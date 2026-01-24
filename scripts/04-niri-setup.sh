#!/bin/bash

# ==============================================================================
# 04-niri-setup.sh - Niri Desktop (Restored FZF & Robust AUR)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

DEBUG=${DEBUG:-0}
CN_MIRROR=${CN_MIRROR:-0}
UNDO_SCRIPT="$SCRIPT_DIR/niri-undochange.sh"

check_root

# --- [HELPER FUNCTIONS] ---


# 2. Critical Failure Handler (The "Big Red Box")
# 2. Critical Failure Handler (The "Big Red Box")
critical_failure_handler() {
  local failed_reason="$1"
  trap - ERR

  echo ""
  echo -e "\033[0;31m################################################################\033[0m"
  echo -e "\033[0;31m#                                                              #\033[0m"
  echo -e "\033[0;31m#   CRITICAL INSTALLATION FAILURE DETECTED                     #\033[0m"
  echo -e "\033[0;31m#                                                              #\033[0m"
  echo -e "\033[0;31m#   Reason: $failed_reason\033[0m"
  echo -e "\033[0;31m#                                                              #\033[0m"
  echo -e "\033[0;31m#   OPTIONS:                                                   #\033[0m"
  echo -e "\033[0;31m#   1. Restore snapshot (Undo changes & Exit)                  #\033[0m"
  echo -e "\033[0;31m#   2. Retry / Re-run script                                   #\033[0m"
  echo -e "\033[0;31m#   3. Abort (Exit immediately)                                #\033[0m"
  echo -e "\033[0;31m#                                                              #\033[0m"
  echo -e "\033[0;31m################################################################\033[0m"
  echo ""

  while true; do
    read -p "Select an option [1-3]: " -r choice
    case "$choice" in
    1)
      # Option 1: Restore Snapshot
      if [ -f "$UNDO_SCRIPT" ]; then
        warn "Executing recovery script..."
        bash "$UNDO_SCRIPT"
        exit 1
      else
        error "Recovery script missing! You are on your own."
        exit 1
      fi
      ;;
    2)
      # Option 2: Re-run Script
      warn "Restarting installation script..."
      echo "-----------------------------------------------------"
      sleep 1
      exec "$0" "$@"
      ;;
    3)
      # Option 3: Exit
      warn "User chose to abort."
      warn "Please fix the issue manually before re-running."
      error "Installation aborted."
      exit 1
      ;;
    *) 
      echo "Invalid input. Please enter 1, 2, or 3." 
      ;;
    esac
  done
}

# 3. Robust Package Installation with Retry Loop
ensure_package_installed() {
  local pkg="$1"
  local context="$2" # e.g., "Repo" or "AUR"
  local max_attempts=3
  local attempt=1
  local install_success=false

  # 1. Check if already installed
  if pacman -Q "$pkg" &>/dev/null; then
    return 0
  fi

  # 2. Retry Loop
  while [ $attempt -le $max_attempts ]; do
    if [ $attempt -gt 1 ]; then
      warn "Retrying '$pkg' ($context)... (Attempt $attempt/$max_attempts)"
      sleep 3 # Cooldown
    else
      log "Installing '$pkg' ($context)..."
    fi

    # Try installation
    if as_user yay -S --noconfirm --needed --answerdiff=None --answerclean=None "$pkg"; then
      install_success=true
      break
    else
      warn "Attempt $attempt/$max_attempts failed for '$pkg'."
    fi

    ((attempt++))
  done

  # 3. Final Verification
  if [ "$install_success" = true ] && pacman -Q "$pkg" &>/dev/null; then
    success "Installed '$pkg'."
  else
    critical_failure_handler "Failed to install '$pkg' after $max_attempts attempts."
  fi
}

section "Phase 4" "Niri Desktop Environment"

# ==============================================================================
# STEP 0: Safety Checkpoint
# ==============================================================================

# Enable Trap
trap 'critical_failure_handler "Script Error at Line $LINENO"' ERR

# ==============================================================================
# STEP 1: Identify User & DM Check
# ==============================================================================
log "Identifying user..."
DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
TARGET_USER="${DETECTED_USER:-$(read -p "Target user: " u && echo $u)}"
HOME_DIR="/home/$TARGET_USER"
info_kv "Target" "$TARGET_USER"

# DM Check
KNOWN_DMS=("gdm" "sddm" "lightdm" "lxdm" "slim" "xorg-xdm" "ly" "greetd")
SKIP_AUTOLOGIN=false
DM_FOUND=""
for dm in "${KNOWN_DMS[@]}"; do
  if pacman -Q "$dm" &>/dev/null; then
    DM_FOUND="$dm"
    break
  fi
done

if [ -n "$DM_FOUND" ]; then
  info_kv "Conflict" "${H_RED}$DM_FOUND${NC}"
  SKIP_AUTOLOGIN=true
else
  read -t 20 -p "$(echo -e "   ${H_CYAN}Enable TTY auto-login? [Y/n] (Default Y): ${NC}")" choice || true
  [[ "${choice:-Y}" =~ ^[Yy]$ ]] && SKIP_AUTOLOGIN=false || SKIP_AUTOLOGIN=true
fi

# ==============================================================================
# STEP 2: Core Components
# ==============================================================================
section "Step 1/9" "Core Components"
PKGS="niri xdg-desktop-portal-gnome fuzzel kitty firefox libnotify mako polkit-gnome"
exe pacman -S --noconfirm --needed $PKGS

log "Configuring Firefox Policies..."
POL_DIR="/etc/firefox/policies"
exe mkdir -p "$POL_DIR"
echo '{ "policies": { "Extensions": { "Install": ["https://addons.mozilla.org/firefox/downloads/latest/pywalfox/latest.xpi"] } } }' >"$POL_DIR/policies.json"
exe chmod 755 "$POL_DIR" && exe chmod 644 "$POL_DIR/policies.json"

# ==============================================================================
# STEP 3: File Manager
# ==============================================================================
section "Step 2/9" "File Manager"
exe pacman -S --noconfirm --needed ffmpegthumbnailer gvfs-smb nautilus-open-any-terminal file-roller gnome-keyring gst-plugins-base gst-plugins-good gst-libav nautilus

if [ ! -f /usr/bin/gnome-terminal ] || [ -L /usr/bin/gnome-terminal ]; then
  exe ln -sf /usr/bin/kitty /usr/bin/gnome-terminal
fi

# Nautilus Nvidia/Input Fix
configure_nautilus_user

section "Step 3/9" "Temp sudo file"

SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_temp"
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" >"$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"
log "Temp sudo file created..."
# ==============================================================================
# STEP 5: Dependencies (RESTORED FZF)
# ==============================================================================
section "Step 4/9" "Dependencies"
LIST_FILE="$PARENT_DIR/niri-applist.txt"

# Ensure tools
command -v fzf &>/dev/null || pacman -S --noconfirm fzf >/dev/null 2>&1

if [ -f "$LIST_FILE" ]; then
  mapfile -t DEFAULT_LIST < <(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | sed 's/#.*//; s/AUR://g' | xargs -n1)

  if [ ${#DEFAULT_LIST[@]} -eq 0 ]; then
    warn "App list is empty. Skipping."
    PACKAGE_ARRAY=()
  else
    echo -e "\n   ${H_YELLOW}>>> Default installation in 60s. Press ANY KEY to customize...${NC}"

    if read -t 60 -n 1 -s -r; then
      # --- [RESTORED] Original FZF Selection Logic ---
      clear
      log "Loading package list..."

      SELECTED_LINES=$(grep -vE "^\s*#|^\s*$" "$LIST_FILE" |
        sed -E 's/[[:space:]]+#/\t#/' |
        fzf --multi \
          --layout=reverse \
          --border \
          --margin=1,2 \
          --prompt="Search Pkg > " \
          --pointer=">>" \
          --marker="* " \
          --delimiter=$'\t' \
          --with-nth=1 \
          --bind 'load:select-all' \
          --bind 'ctrl-a:select-all,ctrl-d:deselect-all' \
          --info=inline \
          --header="[TAB] TOGGLE | [ENTER] INSTALL | [CTRL-D] DE-ALL | [CTRL-A] SE-ALL" \
          --preview "echo {} | cut -f2 -d$'\t' | sed 's/^# //'" \
          --preview-window=right:50%:wrap:border-left \
          --color=dark \
          --color=fg+:white,bg+:black \
          --color=hl:blue,hl+:blue:bold \
          --color=header:yellow:bold \
          --color=info:magenta \
          --color=prompt:cyan,pointer:cyan:bold,marker:green:bold \
          --color=spinner:yellow)

      clear

      if [ -z "$SELECTED_LINES" ]; then
        warn "User cancelled selection. Installing NOTHING."
        PACKAGE_ARRAY=()
      else
        PACKAGE_ARRAY=()
        while IFS= read -r line; do
          raw_pkg=$(echo "$line" | cut -f1 -d$'\t' | xargs)
          clean_pkg="${raw_pkg#AUR:}"
          [ -n "$clean_pkg" ] && PACKAGE_ARRAY+=("$clean_pkg")
        done <<<"$SELECTED_LINES"
      fi
      # -----------------------------------------------
    else
      log "Auto-confirming ALL packages."
      PACKAGE_ARRAY=("${DEFAULT_LIST[@]}")
    fi
  fi

  # --- Installation Loop ---
  if [ ${#PACKAGE_ARRAY[@]} -gt 0 ]; then
    BATCH_LIST=()
    AUR_LIST=()
    info_kv "Target" "${#PACKAGE_ARRAY[@]} packages scheduled."

    for pkg in "${PACKAGE_ARRAY[@]}"; do
      [ "$pkg" == "imagemagic" ] && pkg="imagemagick"
      [[ "$pkg" == "AUR:"* ]] && AUR_LIST+=("${pkg#AUR:}") || BATCH_LIST+=("$pkg")
    done

    # 1. Batch Install Repo Packages
    if [ ${#BATCH_LIST[@]} -gt 0 ]; then
      log "Phase 1: Batch Installing Repo Packages..."
      as_user yay -Syu --noconfirm --needed --answerdiff=None --answerclean=None "${BATCH_LIST[@]}" || true

      # Verify Each
      for pkg in "${BATCH_LIST[@]}"; do
        ensure_package_installed "$pkg" "Repo"
      done
    fi

    # 2. Sequential AUR Install
    if [ ${#AUR_LIST[@]} -gt 0 ]; then
      log "Phase 2: Installing AUR Packages (Sequential)..."
      for pkg in "${AUR_LIST[@]}"; do
        ensure_package_installed "$pkg" "AUR"
      done
    fi

    # Waybar fallback
    if ! command -v waybar &>/dev/null; then
      warn "Waybar missing. Installing stock..."
      exe pacman -S --noconfirm --needed waybar
    fi
  else
    warn "No packages selected."
  fi
else
  warn "niri-applist.txt not found."
fi

# ==============================================================================
# STEP 6: Dotfiles (Linked via Symlinks)
# ==============================================================================
section "Step 5/9" "Deploying Dotfiles"

# 1. 定义新的持久化仓库路径
REPO_GITHUB="https://github.com/SHORiN-KiWATA/ShorinArchExperience-ArchlinuxGuide.git"
REPO_GITEE="https://gitee.com/shorinkiwata/ShorinArchExperience-ArchlinuxGuide.git"
# 修改：不再使用 /tmp，而是放到用户的 .local/share 下
DOTFILES_REPO="$HOME_DIR/.local/share/shorin-niri"

# 2. Git Clone 或 Pull 处理函数
prepare_repository() {
  if [ -d "$DOTFILES_REPO/.git" ]; then
    log "Repository exists. Updating..."
    # 尝试更新，如果失败则删除重下
    if ! as_user git -C "$DOTFILES_REPO" pull --ff-only; then
      warn "Update failed. Resetting repository..."
      rm -rf "$DOTFILES_REPO"
    else
      success "Repository updated."
      return 0
    fi
  fi

  # 如果目录不存在或已被删除，则进行克隆
  log "Cloning configuration to $DOTFILES_REPO..."
  if ! as_user git clone "$REPO_GITHUB" "$DOTFILES_REPO"; then
    warn "GitHub failed. Trying Gitee..."
    rm -rf "$DOTFILES_REPO"
    if ! as_user git clone "$REPO_GITEE" "$DOTFILES_REPO"; then
      critical_failure_handler "Failed to clone dotfiles from any source."
    fi
  fi
}

# 3. 核心链接函数
link_dotfiles() {
  local src_root="$1"
  local dest_root="$2"
  local exclude_list="$3"

  log "Linking files from $(basename "$src_root")..."

  # 遍历源目录下的所有文件和文件夹（包含隐藏文件）
  find "$src_root" -mindepth 1 -maxdepth 1 -not -path '*/.git*' | while read -r item; do
    local item_name
    item_name=$(basename "$item")

    # 检查是否在排除列表中
    if echo "$exclude_list" | grep -qw "$item_name"; then
      log "Skipping excluded: $item_name"
      continue
    fi

    # 特殊处理 .config 目录：不直接链接 .config 文件夹本身，而是链接其子目录
    # 这样可以防止覆盖用户 .config 中其他不相关的软件配置
    if [ "$item_name" == ".config" ]; then
        as_user mkdir -p "$dest_root/.config"
        # 递归调用处理 .config 内部
        link_dotfiles "$item/.config" "$dest_root/.config" "$exclude_list"
        continue
    fi
    
    # 特殊处理 .local 目录：逻辑同上
    if [ "$item_name" == ".local" ]; then
        as_user mkdir -p "$dest_root/.local"
        # 这里假设只处理 .local/bin 或 .local/share，简单起见递归链接内部
        # 如果只想链接 .local/bin 下的脚本，可以写得更细，这里采用目录级链接
        # 这里的实现方式是递归遍历 .local 下的一级目录（如 bin, share）
        find "$item" -mindepth 1 -maxdepth 1 | while read -r local_sub; do
             local sub_name=$(basename "$local_sub")
             as_user mkdir -p "$dest_root/.local"
             # 建立链接： 例如 .local/share/fonts -> ~/.local/share/fonts
             local target="$dest_root/.local/$sub_name"
             # 移除旧的目标（如果是文件夹则移除，如果是文件也移除）
             [ -e "$target" ] || [ -L "$target" ] && as_user rm -rf "$target"
             as_user ln -sf "$local_sub" "$target"
        done
        continue
    fi

    # 常规文件/文件夹链接逻辑
    local target="$dest_root/$item_name"
    
    # 如果目标存在，先删除（备份已在外部完成）
    if [ -e "$target" ] || [ -L "$target" ]; then
      # 使用 rm -rf 确保无论是软链还是实体目录都被移除
      as_user rm -rf "$target"
    fi

    # 创建软链接
    as_user ln -sf "$item" "$target"
    # echo "Linked: $item -> $target" # Debug output
  done
}

# --- 执行流程 ---

prepare_repository

if [ -d "$DOTFILES_REPO/dotfiles" ]; then
  # 准备排除列表
  EXCLUDE_LIST=""
  if [ "$TARGET_USER" != "shorin" ]; then
    EXCLUDE_FILE="$PARENT_DIR/exclude-dotfiles.txt"
    if [ -f "$EXCLUDE_FILE" ]; then
      log "Loading exclusions..."
      # 读取排除文件内容到变量，去除回车和注释
      EXCLUDE_LIST=$(grep -vE "^\s*#|^\s*$" "$EXCLUDE_FILE" | tr '\n' ' ')
    fi
  fi

  # 备份现有配置
  log "Backing up existing configs..."
  as_user tar -czf "$HOME_DIR/config_backup_$(date +%s).tar.gz" -C "$HOME_DIR" .config

  # 执行链接函数 (针对 .config 目录特殊处理逻辑在函数内)
  # 注意：这里我们传入 repo/dotfiles 作为源，HOME 作为目标
  # 函数会自动处理 .config 内部的子文件夹链接
  
  # 这里为了适配函数的递归逻辑，我们需要微调一下调用方式。
  # 原始结构: dotfiles/.config/APP
  # 我们遍历 dotfiles/*
  
  # 调用链接函数
  link_dotfiles "$DOTFILES_REPO/dotfiles" "$HOME_DIR" "$EXCLUDE_LIST"

  # --- Post-Process (修正与清理) ---
  if [ "$TARGET_USER" != "shorin" ]; then
    # 1. 处理 output.kdl
    # 该文件会被 truncate 清空，为了不影响 Git 仓库，必须断开软链
    OUTPUT_KDL="$HOME_DIR/.config/niri/output.kdl"
    if [ -L "$OUTPUT_KDL" ]; then
        as_user rm "$OUTPUT_KDL"
        as_user touch "$OUTPUT_KDL" # 创建为空文件
    else
        as_user truncate -s 0 "$OUTPUT_KDL" 2>/dev/null
    fi
    
    # 2. 处理 Bookmarks
    # 该文件会被 sed 修改，为了不污染 Git 仓库，必须断开软链并复制
    BOOKMARKS_FILE="$HOME_DIR/.config/gtk-3.0/bookmarks"
    REPO_BOOKMARKS="$DOTFILES_REPO/dotfiles/.config/gtk-3.0/bookmarks"
    
    if [ -L "$BOOKMARKS_FILE" ] || [ -f "$REPO_BOOKMARKS" ]; then
        # 移除软链接
        [ -L "$BOOKMARKS_FILE" ] && as_user rm "$BOOKMARKS_FILE"
        # 从仓库复制实体文件过来
        as_user cp "$REPO_BOOKMARKS" "$BOOKMARKS_FILE"
        
        # 执行替换操作
        as_user sed -i "s/shorin/$TARGET_USER/g" "$BOOKMARKS_FILE"
        log "Updated GTK bookmarks (converted symlink to physical file)."
    fi
  fi

  # Fix Symlinks & Permissions (GTK Themes)
  # 这些是内部相对链接，保持原样即可
  GTK4="$HOME_DIR/.config/gtk-4.0"
  THEME="$HOME_DIR/.themes/adw-gtk3-dark/gtk-4.0"
  
  # 确保目录存在（如果是软链过来的，目录肯定存在）
  if [ -d "$GTK4" ]; then
      as_user rm -f "$GTK4/gtk.css" "$GTK4/gtk-dark.css"
      as_user ln -sf "$THEME/gtk-dark.css" "$GTK4/gtk-dark.css"
      as_user ln -sf "$THEME/gtk.css" "$GTK4/gtk.css"
  fi

  if command -v flatpak &>/dev/null; then
    as_user flatpak override --user --filesystem="$HOME_DIR/.themes"
    as_user flatpak override --user --filesystem=xdg-config/gtk-4.0
    as_user flatpak override --user --filesystem=xdg-config/gtk-3.0
    as_user flatpak override --user --env=GTK_THEME=adw-gtk3-dark
    as_user flatpak override --user --filesystem=xdg-config/fontconfig
  fi
  success "Dotfiles Linked."
else
  warn "Dotfiles missing in repo directory."
fi

# ==============================================================================
# STEP 7: Wallpapers & Templates
# ==============================================================================
section "Step 6/9" "Wallpapers"
# 修改：路径引用从 TEMP_DIR 改为 DOTFILES_REPO
if [ -d "$DOTFILES_REPO/wallpapers" ]; then
  as_user mkdir -p "$HOME_DIR/Pictures/Wallpapers"
  # 壁纸可以选择 cp (复制) 或 ln (链接)。通常复制比较好，防止误删仓库文件。
  # 这里保留复制逻辑，源路径改变即可。
  as_user cp -rf "$DOTFILES_REPO/wallpapers/." "$HOME_DIR/Pictures/Wallpapers/"
  
  as_user mkdir -p "$HOME_DIR/Templates"
  as_user touch "$HOME_DIR/Templates/new"
  as_user touch "$HOME_DIR/Templates/new.sh"
  # 修正权限问题，追加写入最好确保文件归属
  echo "#!/bin/bash" | as_user tee "$HOME_DIR/Templates/new.sh" >/dev/null
  as_user chmod +x "$HOME_DIR/Templates/new.sh"
  success "Installed."
fi

# ==============================================================================
# STEP 8: Hardware Tools
# ==============================================================================
section "Step 7/9" "Hardware"
if pacman -Q ddcutil &>/dev/null; then
  gpasswd -a "$TARGET_USER" i2c
  lsmod | grep -q i2c_dev || echo "i2c-dev" >/etc/modules-load.d/i2c-dev.conf
fi
if pacman -Q swayosd &>/dev/null; then
  systemctl enable --now swayosd-libinput-backend.service >/dev/null 2>&1
fi
success "Tools configured."

# ==============================================================================
# STEP 9: Cleanup & Auto-Login
# ==============================================================================
section "Final" "Cleanup & Boot"
rm -f "$SUDO_TEMP_FILE"

SVC_DIR="$HOME_DIR/.config/systemd/user"
SVC_FILE="$SVC_DIR/niri-autostart.service"
LINK="$SVC_DIR/default.target.wants/niri-autostart.service"

if [ "$SKIP_AUTOLOGIN" = true ]; then
  log "Auto-login skipped."
  as_user rm -f "$LINK" "$SVC_FILE"
else
  log "Configuring TTY Auto-login..."
  mkdir -p "/etc/systemd/system/getty@tty1.service.d"
  echo -e "[Service]\nExecStart=\nExecStart=-/sbin/agetty --noreset --noclear --autologin $TARGET_USER - \${TERM}" >"/etc/systemd/system/getty@tty1.service.d/autologin.conf"

  as_user mkdir -p "$(dirname "$LINK")"
  cat <<EOT >"$SVC_FILE"
[Unit]
Description=Niri Session Autostart
After=graphical-session-pre.target
[Service]
ExecStart=/usr/bin/niri-session
Restart=on-failure
[Install]
WantedBy=default.target
EOT
  as_user ln -sf "../niri-autostart.service" "$LINK"
  chown -R "$TARGET_USER" "$SVC_DIR"
  success "Enabled."
fi

trap - ERR
log "Module 04 completed."