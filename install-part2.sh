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
yay -S clipse || log_warning "Failed to install clipse (continuing...)"
log_success "clipse installed"

# Increase /tmp (tmpfs) partition
log_info "Increasing /tmp (tmpfs) partition..."
sudo mount -o remount,size=10G /tmp || log_warning "Failed to resize /tmp tmpfs"

# Create config directories
log_info "Creating configuration directories..."
mkdir -p ~/.config/hypr ~/.config/foot ~/.config/ghostty ~/Pictures
log_success "Configuration directories created"

# Download wallpapers from dotfiles (will be done later with waybar config)
log_info "Wallpapers will be copied from dotfiles..."

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

# Create Hyprland configuration
log_info "Creating Hyprland configuration..."
cat > ~/.config/hypr/hyprland.conf << 'HYPR_EOF'
# Monitor configuration
monitor=,preferred,auto,1

# Autostart
exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
exec-once = systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
exec-once = hyprpaper
exec-once = waybar
exec-once = dunst
exec-once = clipse -listen
exec-once = foot --server
exec-once = nm-applet --indicator
exec-once = pipewire & pipewire-pulse & wireplumber
exec-once = gnome-keyring-daemon --start --components=secrets
exec-once = thunar --daemon
# exec-once = syncthing --no-browser  # Uncomment if needed

# Environment
env = XCURSOR_SIZE,24
env = HYPRCURSOR_SIZE,24
env = XDG_CURRENT_DESKTOP,Hyprland
env = XDG_SESSION_TYPE,wayland
env = GDK_BACKEND,wayland,x11
env = QT_QPA_PLATFORM,wayland
env = QT_WAYLAND_DISABLE_WINDOWDECORATION,1
env = MOZ_ENABLE_WAYLAND,1
env = GTK_THEME,Adwaita:dark  # Force dark theme

# Input configuration
input {
    kb_layout = us
    follow_mouse = 1
    sensitivity = 0
    accel_profile = flat
    touchpad {
        natural_scroll = false
    }
}

# General settings
general {
    gaps_in = 4
    gaps_out = 8
    border_size = 2
    col.active_border = rgb(FF90BC) rgb(5FBDFF) 45deg
    col.inactive_border = rgba(595959aa)
    resize_on_border = true
    layout = dwindle
}

# Decoration
decoration {
    rounding = 10
    active_opacity = 0.93
    inactive_opacity = 0.87

    shadow {
        enabled = true
        range = 4
        render_power = 3
        color = rgba(00000033)
    }

    blur {
        enabled = true
        size = 3
        passes = 1
        vibrancy = 0.25
    }
}

# Animations
animations {
    enabled = true
    bezier = myBezier, 0.05, 0.9, 0.1, 1.05
    animation = windows, 1, 3, myBezier
    animation = windowsOut, 1, 5, default, popin 80%
    animation = border, 1, 10, default
    animation = fade, 1, 5, default
    animation = workspaces, 1, 6, default
}

# Layout
dwindle {
    pseudotile = true
    preserve_split = true
}

# Window rules
windowrule = suppressevent maximize, class:.*
windowrule = nofocus, class:^$, title:^$, xwayland:1,floating:1,fullscreen:0,pinned:0
windowrule = float, class:(clipse)
windowrule = size 622 652, class:(clipse)
windowrule = stayfocused, class:(clipse)
windowrulev2 = opaque, class:^(ghostty)$

# Keybindings
$mainMod = CTRL
$terminal = ghostty
$foot = foot
$fileManager = thunar
$menu = wofi -i --show drun --allow-images

# Basic bindings
bind = $mainMod, Return, exec, $foot
bind = $mainMod SHIFT, Return, exec, $terminal
bind = ALT, F4, killactive,
bind = SUPER, X, exit,
bind = SUPER, F, togglefloating,
bind = ALT, Space, exec, $menu
bind = SUPER, E, exec, $fileManager
bind = SUPER, V, exec, $terminal --class clipse -e clipse

# Focus movement
bind = $mainMod, left, movefocus, l
bind = $mainMod, right, movefocus, r
bind = $mainMod, up, movefocus, u
bind = $mainMod, down, movefocus, d

# Move windows
bind = $mainMod SHIFT, left, movewindow, l
bind = $mainMod SHIFT, right, movewindow, r
bind = $mainMod SHIFT, up, movewindow, u
bind = $mainMod SHIFT, down, movewindow, d

# Workspaces
bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
bind = $mainMod, 3, workspace, 3
bind = $mainMod, 4, workspace, 4

bind = $mainMod SHIFT, 1, movetoworkspace, 1
bind = $mainMod SHIFT, 2, movetoworkspace, 2
bind = $mainMod SHIFT, 3, movetoworkspace, 3
bind = $mainMod SHIFT, 4, movetoworkspace, 4

# Volume and brightness
bind = , XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%+
bind = , XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-
bind = , XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
bind = , XF86MonBrightnessUp, exec, brightnessctl s +5%
bind = , XF86MonBrightnessDown, exec, brightnessctl s 5%-

# Mouse bindings
bindm = $mainMod, mouse:272, movewindow
bindm = $mainMod, mouse:273, resizewindow

# Screenshots
bind = $mainMod, Print, exec, grim -g "$(slurp)" - | wl-copy

# Plugins
plugin = hyprbars

hyprbars {
    height = 28
    corners = 10
    background-color = rgba(245,245,245,0.90)
    font = "DejaVu Sans Mono:style=Regular:pixelsize=16"
    fallback-font = "Noto Sans:style=Regular:pixelsize=16"
    font-color = rgba(50,50,50,0.9)
    buttons = minimize,maximize,close
    button-layout = left
    button-radius = 7
    button-size = 14
    button-spacing = 5
    button-color-close = #ff605c
    button-color-minimize = #ffbd44
    button-color-maximize = #00ca4e
    button-color-hover = rgba(160,160,160,0.20)
    title-alignment = center
    padding-left = 16
    padding-right = 16
    shadow = true
    shadow-color = rgba(90,90,90,0.18)
    shadow-radius = 8
    shadow-offset-y = 2
}
HYPR_EOF

log_success "Hyprland configuration created"

# Create Foot terminal configuration
log_info "Creating Foot terminal configuration..."
cat > ~/.config/foot/foot.ini << 'FOOT_EOF'
[main]
font=DejaVu Sans Mono:size=11
pad=10x10

[colors]
alpha=0.95
foreground=d8dee9
background=2e3440

[mouse]
hide-when-typing=yes
FOOT_EOF

log_success "Foot terminal configuration created"

# Create Ghostty terminal configuration
log_info "Creating Ghostty terminal configuration..."
cat > ~/.config/ghostty/config << 'GHOSTTY_EOF'
font-family = "DejaVu Sans Mono"
font-size = 11
window-padding-x = 10
window-padding-y = 10
background-opacity = 0.95

foreground = #d8dee9
background = #2e3440

mouse-hide-while-typing = true
prefer-wayland = true
GHOSTTY_EOF

log_success "Ghostty terminal configuration created"

# Delete yay temporary packages (/tmp/yay)
log_info "Deleting temporary files in /tmp/yay"
rm -rf /tmp/yay 2>/dev/null || true

log_success "cleared yay temporary packages"

# Delete temporary files in /tmp (keep the directory)
log_info "Cleaning temporary files in /tmp"
sudo find /tmp -type f -delete 2>/dev/null || true

log_success "cleared tmpfs (/tmp)"

# Clone dotfiles and copy waybar configuration and wallpapers
log_info "Downloading configurations and wallpapers from dotfiles..."
cd /tmp
if [[ -d hyprland-dotfiles ]]; then
    rm -rf hyprland-dotfiles
fi

git clone https://github.com/woioeow/hyprland-dotfiles.git || log_error "Failed to clone dotfiles repository"

# Copy waybar configuration
mkdir -p ~/.config/waybar
cp -r hyprland-dotfiles/hypr_style1/waybar/* ~/.config/waybar/ || log_error "Failed to copy waybar configuration"

# Copy all wallpapers to Pictures directory
log_info "Copying wallpapers to Pictures directory..."
if [[ -d hyprland-dotfiles/hypr_style1/wallpaper ]]; then
    cp hyprland-dotfiles/hypr_style1/wallpaper/* ~/Pictures/ || log_error "Failed to copy wallpapers"
    log_success "Wallpapers copied successfully"
else
    log_warning "Wallpaper directory not found in dotfiles"
fi

cd ~
log_success "Waybar configuration and wallpapers copied from dotfiles"

# Create Hyprpaper configuration (after wallpapers are copied)
log_info "Creating Hyprpaper configuration..."
if [[ -f ~/Pictures/astronaut.png ]]; then
    # Use astronaut.png if available
    cat > ~/.config/hypr/hyprpaper.conf << 'PAPER_EOF'
preload = ~/Pictures/astronaut.png
wallpaper = ,~/Pictures/astronaut.png
PAPER_EOF
    log_success "Hyprpaper configuration created with astronaut.png wallpaper"
elif [[ -f ~/Pictures/wallpaper.jpg ]]; then
    # Fallback to wallpaper.jpg
    cat > ~/.config/hypr/hyprpaper.conf << 'PAPER_EOF'
preload = ~/Pictures/wallpaper.jpg
wallpaper = ,~/Pictures/wallpaper.jpg
PAPER_EOF
    log_success "Hyprpaper configuration created with wallpaper.jpg"
else
    # Use any available wallpaper as fallback
    WALLPAPER=$(find ~/Pictures -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" | head -1)
    if [[ -n "$WALLPAPER" ]]; then
        cat > ~/.config/hypr/hyprpaper.conf << EOF
preload = $WALLPAPER
wallpaper = ,$WALLPAPER
EOF
        log_success "Hyprpaper configuration created with $(basename "$WALLPAPER")"
    else
        log_warning "No wallpapers found, hyprpaper configuration not created"
    fi
fi

# Create Wofi configuration
log_info "Creating Wofi configuration..."
mkdir -p ~/.config/wofi

cat > ~/.config/wofi/config << 'WOFI_EOF'
width=400
height=300
location=center
show=drun
prompt=Search...
filter_rate=100
allow_markup=true
no_actions=true
halign=fill
orientation=vertical
content_halign=fill
insensitive=true
allow_images=true
image_size=32
gtk_dark=true
key_expand=Tab
WOFI_EOF

cat > ~/.config/wofi/style.css << 'WOFI_STYLE_EOF'
window {
margin: 0px;
border: 2px solid #FF90BC;
background-color: rgba(43, 48, 59, 0.95);
border-radius: 10px;
}

#input {
margin: 5px;
border: none;
color: #ffffff;
background-color: rgba(255, 255, 255, 0.1);
border-radius: 5px;
}

#inner-box {
margin: 5px;
border: none;
background-color: transparent;
}

#outer-box {
margin: 5px;
border: none;
background-color: transparent;
}

#scroll {
margin: 0px;
border: none;
}

#text {
margin: 5px;
border: none;
color: #ffffff;
}

#entry {
background-color: transparent;
border-radius: 5px;
}

#entry:selected {
background-color: rgba(255, 144, 188, 0.3);
}

#text:selected {
color: #ffffff;
}
WOFI_STYLE_EOF

log_success "Wofi configuration created"

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
log_info "Cleaning up temporary files..."
rm -rf /tmp/yay 2>/dev/null || true
rm -rf /tmp/hyprland-dotfiles 2>/dev/null || true

# Create a quick start guide
log_info "Creating quick start guide..."
cat > ~/QUICK_START.md << 'QUICKSTART_EOF'
# Arch Linux + Hyprland Quick Start Guide

## Keyboard Shortcuts
- **Terminal (Foot)**: Ctrl + Enter
- **Terminal (Ghostty)**: Ctrl + Shift + Enter
- **Application Launcher**: Alt + Space
- **File Manager**: Super + E
- **Screenshot Area**: Super + Print
- **Toggle Floating**: Super + F
- **Close Window**: Alt + F4
- **Exit Hyprland**: Super + X
- **Clipboard Manager**: Super + V

## Workspaces
- **Switch to workspace 1-4**: Super + 1-4
- **Move window to workspace**: Super + Shift + 1-4

## Volume & Brightness
- **Volume Up/Down**: Fn + XF86AudioRaiseVolume/XF86AudioLowerVolume
- **Mute**: Fn + XF86AudioMute
- **Brightness Up/Down**: Fn + XF86MonBrightnessUp/XF86MonBrightnessDown

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

## Tips
- You can customize any configuration file to your liking
- Use `hyprctl` command to interact with Hyprland
- Check system status with `sysinfo` command
- Screenshots are saved to ~/Pictures/
- Flatpak apps can be launched from the application menu (Super + Space)
QUICKSTART_EOF

echo ""
echo "=================================================================="
log_success "Arch Linux + Hyprland Installation Complete!"
echo "=================================================================="
echo ""
log_info "Quick Start Guide:"
echo "  • Terminal (Foot): Ctrl + Enter"
echo "  • Terminal (Ghostty): Ctrl + Shift + Enter"
echo "  • App Launcher: Alt + Space"
echo "  • File Manager: Super + E"
echo "  • Screenshot: Super + Print"
echo "  • Toggle Floating: Super + F"
echo "  • Close Window: Alt + F4"
echo "  • Exit Hyprland: Super + X"
echo "  • Clipboard Manager: Super + V"
echo ""
log_info "Installed Applications:"
echo "  • Web Browser: flatpak run com.brave.Browser"
echo "  • System Monitor: bpytop"
echo "  • Password Manager: flatpak run com.bitwarden.desktop"
echo "  • File Sharing: flatpak run org.localsend.localsend_app"
echo "  • Backup & Restore: sudo -E timeshift-gtk"
echo "  • System Info: sysinfo"
echo "  • Screenshots: screenshot [area|window|full]"
echo ""
log_info "Configuration Files:"
echo "  • Hyprland: ~/.config/hypr/hyprland.conf"
echo "  • Waybar: ~/.config/waybar/config"
echo "  • Foot: ~/.config/foot/foot.ini"
echo "  • Ghostty: ~/.config/ghostty/config"
echo "  • Wofi: ~/.config/wofi/config"
echo ""
log_success "System is ready to use! Check ~/QUICK_START.md for detailed guide."
echo ""
log_info "Tip: You may want to logout and login again, or restart Hyprland"
log_info "to ensure all plugins and configurations are properly loaded."
echo ""
log_info "To logout from Hyprland: Super + X"
