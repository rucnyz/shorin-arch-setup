#!/bin/bash

# ==============================================================================
# 05-apps.sh - Common Applications Installation (Yay & Flatpak)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

check_root

# ------------------------------------------------------------------------------
# 0. Identify Target User
# ------------------------------------------------------------------------------
log "Step 0/4: Identifying Target User..."

DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)

if [ -n "$DETECTED_USER" ]; then
    TARGET_USER="$DETECTED_USER"
    log "-> Automatically detected target user: ${BOLD}$TARGET_USER${NC}"
else
    read -p "Please enter the target username: " TARGET_USER
fi

HOME_DIR="/home/$TARGET_USER"

# ------------------------------------------------------------------------------
# 1. User Confirmation (Visual Upgrade)
# ------------------------------------------------------------------------------
echo ""
box_title "OPTIONAL: Common Applications" "${H_CYAN}"

echo -e "   This module reads from: ${BOLD}common-applist.txt${NC}"
echo -e "   Format: ${DIM}lines starting with 'flatpak:' use Flatpak, others use Yay.${NC}"
echo ""

read -p "$(echo -e ${H_YELLOW}"   Do you want to install these applications? [Y/n] "${NC})" choice
choice=${choice:-Y}

if [[ ! "$choice" =~ ^[Yy]$ ]]; then
    log "User skipped application installation."
    exit 0
fi

hr

# ------------------------------------------------------------------------------
# 2. Parse App List
# ------------------------------------------------------------------------------
log "Step 2/4: Parsing application list..."

LIST_FILE="$PARENT_DIR/common-applist.txt"
YAY_APPS=()
FLATPAK_APPS=()
FAILED_PACKAGES=() # Initialize failure tracking

if [ -f "$LIST_FILE" ]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        line=$(echo "$line" | tr -d '\r' | xargs)
        # Skip comments and empty lines
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        
        if [[ "$line" == flatpak:* ]]; then
            app_id="${line#flatpak:}"
            FLATPAK_APPS+=("$app_id")
        else
            YAY_APPS+=("$line")
        fi
    done < "$LIST_FILE"
    
    log "-> Queue: ${BOLD}${#YAY_APPS[@]}${NC} Yay packages | ${BOLD}${#FLATPAK_APPS[@]}${NC} Flatpak packages."
else
    warn "File ${BOLD}common-applist.txt${NC} not found. Skipping."
    exit 0
fi

# ------------------------------------------------------------------------------
# 3. Install Applications
# ------------------------------------------------------------------------------

# --- A. Install Yay Apps ---
if [ ${#YAY_APPS[@]} -gt 0 ]; then
    log "Step 3a/4: Installing system packages (Yay)..."
    
    # Configure NOPASSWD
    SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_apps"
    echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDO_TEMP_FILE"
    chmod 440 "$SUDO_TEMP_FILE"
    
    BATCH_LIST="${YAY_APPS[*]}"
    log "-> Attempting batch install..."
    
    # Try Batch
    if runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed --answerdiff=None --answerclean=None $BATCH_LIST; then
        success "All system packages installed successfully."
    else
        warn "Batch install failed. Switching to One-by-One mode..."
        for pkg in "${YAY_APPS[@]}"; do
            # Attempt 1
            if ! runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed --answerdiff=None --answerclean=None "$pkg"; then
                warn "Failed to install '$pkg'. Retrying (Attempt 2/2)..."
                # Attempt 2
                if ! runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed --answerdiff=None --answerclean=None "$pkg"; then
                    error "Failed to install: $pkg"
                    FAILED_PACKAGES+=("yay:$pkg")
                else
                    success "Installed: $pkg (on retry)"
                fi
            else
                # Silent success for one-by-one to keep log clean
                : 
            fi
        done
    fi
    
    rm -f "$SUDO_TEMP_FILE"
fi

# --- B. Install Flatpak Apps ---
if [ ${#FLATPAK_APPS[@]} -gt 0 ]; then
    log "Step 3b/4: Installing Flatpak packages..."
    
    for app in "${FLATPAK_APPS[@]}"; do
        # Attempt 1
        if flatpak install -y flathub "$app" > /dev/null 2>&1; then
            success "Installed: $app"
        else
            warn "Flatpak install failed for '$app'. Waiting 3s to Retry..."
            sleep 3
            # Attempt 2
            if flatpak install -y flathub "$app" > /dev/null 2>&1; then
                success "Installed: $app (on retry)"
            else
                error "Failed to install Flatpak: $app"
                FAILED_PACKAGES+=("flatpak:$app")
            fi
        fi
    done
fi

# ------------------------------------------------------------------------------
# 3.5 Generate Failure Report
# ------------------------------------------------------------------------------
if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
    DOCS_DIR="$HOME_DIR/Documents"
    REPORT_FILE="$DOCS_DIR/安装失败的软件.txt"
    
    if [ ! -d "$DOCS_DIR" ]; then runuser -u "$TARGET_USER" -- mkdir -p "$DOCS_DIR"; fi
    
    echo -e "\n--- Phase 5 (Common Apps) Failures ---" >> "$REPORT_FILE"
    printf "%s\n" "${FAILED_PACKAGES[@]}" >> "$REPORT_FILE"
    chown "$TARGET_USER:$TARGET_USER" "$REPORT_FILE"
    
    echo -e "${H_RED}[ATTENTION]${NC} Some applications failed. Report updated at: ${BOLD}$REPORT_FILE${NC}"
else
    success "All selected applications installed successfully."
fi

# ------------------------------------------------------------------------------
# 4. Steam Locale Fix
# ------------------------------------------------------------------------------
log "Step 4/4: applying Steam locale fix (zh_CN)..."

STEAM_desktop_modified=false

# Method 1: Native Steam
NATIVE_DESKTOP="/usr/share/applications/steam.desktop"
if [ -f "$NATIVE_DESKTOP" ]; then
    if ! grep -q "env LANG=zh_CN.UTF-8" "$NATIVE_DESKTOP"; then
        sed -i 's|^Exec=/usr/bin/steam|Exec=env LANG=zh_CN.UTF-8 /usr/bin/steam|' "$NATIVE_DESKTOP"
        sed -i 's|^Exec=steam|Exec=env LANG=zh_CN.UTF-8 steam|' "$NATIVE_DESKTOP"
        success "Patched Native Steam .desktop file."
        STEAM_desktop_modified=true
    else
        log "-> Native Steam already patched."
    fi
fi

# Method 2: Flatpak Steam
if echo "${FLATPAK_APPS[@]}" | grep -q "com.valvesoftware.Steam" || flatpak list | grep -q "com.valvesoftware.Steam"; then
    flatpak override --env=LANG=zh_CN.UTF-8 com.valvesoftware.Steam
    success "Applied Flatpak Steam environment override."
    STEAM_desktop_modified=true
fi

if [ "$STEAM_desktop_modified" = false ]; then
    log "-> Steam not found. Skipping fix."
fi

log ">>> Phase 5 completed."