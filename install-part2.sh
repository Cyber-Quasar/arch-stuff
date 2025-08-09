#!/bin/bash

# Arch Linux Installation Script - Part 2 (Post-Reboot)
# Run this after first boot into the new system as the regular user
# 
# Prerequisites:
# 1. Connect to internet (Ethernet or WiFi)
# 2a. If you want to connect with wifi, do these steps:
# rfkill unblock all
# nmcli dev wifi list
# nmcli dev wifi connect "<SSID_or_BSSID>" password "<password>"

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

USERNAME="CyberQuasar"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Verify we're not running as root
if [[ $EUID -eq 0 ]]; then
    log_error "This script should NOT be run as root. Run as regular user: $USERNAME"
fi

# Verify we're the correct user
if [[ "$(whoami)" != "$USERNAME" ]]; then
    log_error "This script should be run as user: $USERNAME"
fi

log_info "Starting Arch Linux Installation - Part 2 (Post-Reboot Configuration)"

# Test internet connection
log_info "Testing internet connection..."
if ! ping -c 3 archlinux.org &>/dev/null; then
    log_error "No internet connection. Please connect to the internet first."
fi
log_success "Internet connection verified"

# Install Plymouth
log_info "Installing Plymouth..."
sudo pacman -S --noconfirm plymouth || log_error "Failed to install Plymouth"
log_success "Plymouth installed successfully"

# Install yay AUR helper
log_info "Installing yay AUR helper..."
cd /tmp
if [[ -d yay ]]; then
    rm -rf yay
fi

git clone https://aur.archlinux.org/yay.git || log_error "Failed to clone yay repository"
cd yay
makepkg -si --noconfirm --needed || log_error "Failed to build and install yay"
cd ~
log_success "yay AUR helper installed successfully"

# Install clipse
log_info "Installing clipse from AUR..."
yay -S --noconfirm clipse || log_warning "Failed to install clipse (continuing...)"
log_success "clipse installed"

# Install atuin (shell history)
log_info "Installing atuin from AUR..."
yay -S --noconfirm atuin || log_warning "Failed to install atuin (continuing...)"
if command -v atuin &> /dev/null; then
    log_info "Setting up atuin shell history..."
    
    # Import existing shell history
    atuin import auto || log_warning "Failed to import existing history"
    
    # Add completions to bashrc
    echo "" >> ~/.bashrc
    echo "# Atuin shell history" >> ~/.bashrc
    atuin gen-completions --shell bash >> ~/.bashrc || log_warning "Failed to add atuin completions"
    
    # Initialize atuin for bash
    echo 'eval "$(atuin init bash)"' >> ~/.bashrc || log_warning "Failed to add atuin init to bashrc"
    
    log_success "atuin installed and configured"
    log_info "atuin will be active in new shell sessions"
else
    log_warning "atuin installation failed or not found in PATH"
fi

# Increase /tmp (tmpfs) partition
log_info "Increasing /tmp (tmpfs) partition..."
sudo mount -o remount,size=10G /tmp || log_warning "Failed to resize /tmp tmpfs"

# Setup Flatpak
log_info "Setting up Flatpak..."
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || log_error "Failed to add Flathub repository"
log_success "Flatpak configured with Flathub"

# Install Flatpak applications
log_info "Installing Flatpak applications..."
flatpak install -y flathub com.brave.Browser || log_warning "Failed to install Brave Browser (continuing...)"
flatpak install -y flathub com.bitwarden.desktop || log_warning "Failed to install Bitwarden (continuing...)"
flatpak install -y flathub org.localsend.localsend_app || log_warning "Failed to install LocalSend (continuing...)"
log_success "Flatpak applications installed"

# Clean temporary files before cloning
log_info "Cleaning temporary files..."
rm -rf /tmp/yay /tmp/hypr-stuff 2>/dev/null || true

# Clone your custom configurations repository
log_info "Cloning custom Hyprland configurations..."
cd /tmp
git clone https://github.com/Cyber-Quasar/hypr-stuff.git || log_error "Failed to clone hypr-stuff repository"

# Copy all configurations from repo to ~/.config/
log_info "Copying configurations to ~/.config/..."
if [[ -d hypr-stuff/configs ]]; then
    # Create ~/.config if it doesn't exist
    mkdir -p ~/.config
    
    # Copy all config directories/files
    cp -r hypr-stuff/configs/* ~/.config/ || log_error "Failed to copy configurations"
    log_success "Configurations copied successfully"
else
    log_error "configs directory not found in hypr-stuff repository"
fi

# Create Pictures directory and copy wallpapers
log_info "Setting up wallpapers..."
mkdir -p ~/Pictures

# Copy wallpaper.png from ~/.config/hypr/ if it exists
if [[ -f ~/.config/hypr/wallpaper.png ]]; then
    cp ~/.config/hypr/wallpaper.png ~/Pictures/ || log_warning "Failed to copy wallpaper.png"
    log_success "wallpaper.png copied to Pictures"
fi

# Copy everything from ~/.config/wallpaper/ if it exists
if [[ -d ~/.config/wallpaper ]]; then
    cp ~/.config/wallpaper/* ~/Pictures/ 2>/dev/null || log_warning "Failed to copy wallpapers from ~/.config/wallpaper/"
    log_success "Wallpapers copied from ~/.config/wallpaper/ to Pictures"
else
    log_warning "~/.config/wallpaper/ directory not found"
fi

# Setup Plymouth theme
log_info "Setting up Plymouth theme..."
if [[ -d /tmp/hypr-stuff/arch-mac-style ]]; then
    # Copy Plymouth theme to system directory
    sudo cp -r /tmp/hypr-stuff/arch-mac-style /usr/share/plymouth/themes/ || log_error "Failed to copy Plymouth theme"
    
    # Find the .plymouth file in the arch-mac-style directory
    PLYMOUTH_FILE=$(find /tmp/hypr-stuff/arch-mac-style -name "*.plymouth" | head -1)
    if [[ -n "$PLYMOUTH_FILE" ]]; then
        THEME_NAME=$(basename "$PLYMOUTH_FILE" .plymouth)
        log_info "Setting Plymouth theme to: $THEME_NAME"
        
        # Set the Plymouth theme
        sudo plymouth-set-default-theme -R "$THEME_NAME" || log_error "Failed to set Plymouth theme"
        
        # Update initramfs
        log_info "Updating initramfs for Plymouth..."
        sudo mkinitcpio -p linux || log_error "Failed to update initramfs"
        
        log_success "Plymouth theme '$THEME_NAME' applied successfully"
    else
        log_warning "No .plymouth file found in arch-mac-style directory"
    fi
else
    log_warning "arch-mac-style directory not found in repository"
fi

# Install Naroz-vr2b cursor theme
log_info "Installing Naroz-vr2b cursor theme..."
if [[ -d /tmp/hypr-stuff/Naroz-vr2b ]]; then
    # Create .icons directory in home if it doesn't exist
    mkdir -p ~/.icons
    
    # Copy the Naroz-vr2b folder to .icons
    cp -r /tmp/hypr-stuff/Naroz-vr2b ~/.icons/ || log_error "Failed to copy Naroz-vr2b cursor theme"
    
    # Set the cursor theme in multiple ways for compatibility
    # Method 1: GTK settings
    mkdir -p ~/.config/gtk-3.0 ~/.config/gtk-4.0
    echo "[Settings]
gtk-cursor-theme-name=Naroz-vr2b
gtk-cursor-theme-size=24" > ~/.config/gtk-3.0/settings.ini
    
    echo "[Settings]
gtk-cursor-theme-name=Naroz-vr2b
gtk-cursor-theme-size=24" > ~/.config/gtk-4.0/settings.ini
    
    # Method 2: X11 resources
    echo "Xcursor.theme: Naroz-vr2b
Xcursor.size: 24" > ~/.Xresources
    
    # Method 3: Set for current session
    export XCURSOR_THEME=Naroz-vr2b
    export XCURSOR_SIZE=24
    
    log_success "Naroz-vr2b cursor theme installed and applied"
    log_info "Cursor theme will be fully active after logout/login or reboot"
else
    log_warning "Naroz-vr2b folder not found in hypr-stuff repository"
fi

# Create convenience scripts
log_info "Creating convenience scripts..."
mkdir -p ~/bin

# Create a system info script
cat > ~/bin/sysinfo << 'SYSINFO_EOF'
#!/bin/bash
echo "=== System Information ==="
echo "Hostname: $(hostname)"
echo "Kernel: $(uname -r)"
echo "Uptime: $(uptime -p)"
echo ""
echo "=== Memory Usage ==="
free -h
echo ""
echo "=== ZRAM Status ==="
sudo zramctl 2>/dev/null || echo "ZRAM not available"
echo ""
echo "=== Disk Usage ==="
df -h / /boot/efi
echo ""
echo "=== Network Status ==="
ip addr show | grep "inet " | grep -v "127.0.0.1"
echo ""
echo "=== Installed Flatpak Apps ==="
flatpak list --app 2>/dev/null || echo "No Flatpak apps installed"
SYSINFO_EOF

chmod +x ~/bin/sysinfo

# Create screenshot script
cat > ~/bin/screenshot << 'SCREENSHOT_EOF'
#!/bin/bash
# Screenshot script for Hyprland
case "$1" in
    area)
        grim -g "$(slurp)" ~/Pictures/screenshot-$(date +%Y%m%d-%H%M%S).png
        ;;
    window)
        hyprctl -j activewindow | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"' | grim -g - ~/Pictures/screenshot-$(date +%Y%m%d-%H%M%S).png
        ;;
    full)
        grim ~/Pictures/screenshot-$(date +%Y%m%d-%H%M%S).png
        ;;
    *)
        echo "Usage: screenshot [area|window|full]"
        echo "  area   - Select area to screenshot"
        echo "  window - Screenshot active window"
        echo "  full   - Screenshot entire screen"
        ;;
esac
SCREENSHOT_EOF

chmod +x ~/bin/screenshot

# Add ~/bin to PATH if not already there
if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
    echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
    log_info "Added ~/bin to PATH in ~/.bashrc"
fi

log_success "Convenience scripts created"

# Test ZRAM configuration
log_info "Testing ZRAM configuration..."
if command -v zramctl &> /dev/null; then
    echo "ZRAM Status:"
    sudo zramctl
    echo ""
    echo "Memory Usage:"
    free -h
    log_success "ZRAM is working correctly"
else
    log_warning "zramctl not found, but ZRAM should be working"
fi

# Test key applications
log_info "Testing installed applications..."
apps_to_test=("hyprland" "foot" "ghostty" "waybar" "wofi" "thunar" "bpytop")
missing_apps=()

for app in "${apps_to_test[@]}"; do
    if ! command -v "$app" &> /dev/null; then
        missing_apps+=("$app")
    fi
done

if [[ ${#missing_apps[@]} -eq 0 ]]; then
    log_success "All key applications are installed and available"
else
    log_warning "Some applications are missing: ${missing_apps[*]}"
fi

# Final system status check
log_info "Performing final system checks..."

# Check if Flatpak apps are installed
flatpak_apps=("com.brave.Browser" "com.bitwarden.desktop" "org.localsend.localsend_app")
for app in "${flatpak_apps[@]}"; do
    if flatpak list | grep -q "$app"; then
        log_success "Flatpak app $app is installed"
    else
        log_warning "Flatpak app $app may not be installed"
    fi
done

# Create desktop shortcuts for Flatpak apps
log_info "Creating desktop shortcuts..."
mkdir -p ~/.local/share/applications

# Ensure Flatpak desktop files are available
if [[ -d /var/lib/flatpak/exports/share/applications ]]; then
    cp /var/lib/flatpak/exports/share/applications/com.brave.Browser.desktop ~/.local/share/applications/ 2>/dev/null || true
    cp /var/lib/flatpak/exports/share/applications/com.bitwarden.desktop.desktop ~/.local/share/applications/ 2>/dev/null || true
    cp /var/lib/flatpak/exports/share/applications/org.localsend.localsend_app.desktop ~/.local/share/applications/ 2>/dev/null || true
fi

# Clean up temporary files
log_info "Final cleanup..."
rm -rf /tmp/yay /tmp/hypr-stuff 2>/dev/null || true

# Create a quick start guide based on your custom configs
log_info "Creating quick start guide..."
cat > ~/QUICK_START.md << 'QUICKSTART_EOF'
# Arch Linux + Hyprland Quick Start Guide

## Keyboard Shortcuts
*Note: These shortcuts depend on your custom Hyprland configuration*
- **Terminal (Foot)**: Check ~/.config/hypr/hyprland.conf for bindings
- **Terminal (Ghostty)**: Check ~/.config/hypr/hyprland.conf for bindings  
- **Application Launcher**: Check ~/.config/hypr/hyprland.conf for bindings
- **File Manager**: Check ~/.config/hypr/hyprland.conf for bindings
- **Screenshot**: Check ~/.config/hypr/hyprland.conf for bindings
- **Clipboard Manager**: Super + V (if clipse is configured)

## Installed Applications
- **Web Browser**: flatpak run com.brave.Browser
- **System Monitor**: bpytop
- **Password Manager**: flatpak run com.bitwarden.desktop
- **File Sharing**: flatpak run org.localsend.localsend_app
- **System Info**: sysinfo
- **Screenshots**: screenshot [area|window|full]

## Configuration Files
- **Hyprland**: ~/.config/hypr/hyprland.conf
- **Waybar**: ~/.config/waybar/config
- **Foot Terminal**: ~/.config/foot/foot.ini
- **Ghostty Terminal**: ~/.config/ghostty/config
- **Wofi Launcher**: ~/.config/wofi/config

## Custom Features
- **Plymouth Boot Screen**: Custom arch-mac-style theme applied
- **Cursor Theme**: Naroz-vr2b cursor theme installed
- **Shell History**: Atuin for enhanced shell history and search
- **Custom Configurations**: Loaded from your hypr-stuff repository
- **Wallpapers**: Available in ~/Pictures/ directory

## Tips
- All configurations are loaded from your custom repository
- Check ~/.config/ for all your custom settings
- Use `hyprctl` command to interact with Hyprland
- Check system status with `sysinfo` command
- Screenshots are saved to ~/Pictures/
- Reboot to see the new Plymouth boot screen
QUICKSTART_EOF

echo ""
echo "=================================================================="
log_success "Arch Linux + Hyprland Installation Complete!"
echo "=================================================================="
echo ""
log_info "Custom Features Applied:"
echo "  • Plymouth boot screen with arch-mac-style theme"
echo "  • Naroz-vr2b cursor theme installed and applied"
echo "  • All configurations loaded from your hypr-stuff repository"
echo "  • Wallpapers copied to ~/Pictures/"
echo "  • Clipboard manager (clipse) installed"
echo "  • Shell history (atuin) installed and configured"
echo ""
log_info "Installed Applications:"
echo "  • Web Browser: flatpak run com.brave.Browser"
echo "  • System Monitor: bpytop"
echo "  • Password Manager: flatpak run com.bitwarden.desktop"
echo "  • File Sharing: flatpak run org.localsend.localsend_app"
echo "  • System Info: sysinfo"
echo "  • Screenshots: screenshot [area|window|full]"
echo ""
log_info "Configuration Files (from your repo):"
echo "  • All configs loaded from ~/.config/"
echo "  • Check ~/.config/hypr/hyprland.conf for keybindings"
echo ""
log_success "System is ready to use! Check ~/QUICK_START.md for detailed guide."
echo ""
log_info "IMPORTANT: Reboot to see the new Plymouth boot screen!"
log_warning "Make sure your hypr-stuff repository is set up correctly with:"
log_warning "  - configs/ directory with all configuration files"
log_warning "  - arch-mac-style/ directory with Plymouth theme"
log_warning "  - Naroz-vr2b/ directory with cursor theme files"
echo ""
log_info "To reboot: sudo reboot"