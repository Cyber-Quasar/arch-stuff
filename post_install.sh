#!/bin/bash

# Post-installation script for Hyprland setup with hyprbars
# Download and run this script after completing the base Arch installation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_info "Starting Hyprland post-installation setup with hyprbars..."

# Part 1: System Setup and Dependencies

log_info "Installing build dependencies for hyprpm..."
sudo pacman -S --noconfirm --needed git cmake meson gcc cpio

log_info "Installing yay AUR helper..."
sudo pacman -S --needed --noconfirm git base-devel
git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin
cd /tmp/yay-bin
makepkg -si --noconfirm
cd ~

# Part 2: Install Core Packages

log_info "Installing core packages from official repos..."
sudo pacman -S --noconfirm \
    wayland wayland-protocols libxkbcommon xorg-xwayland \
    mesa libva-intel-driver intel-media-driver libva-utils \
    hyprland hyprpaper xdg-desktop-portal-hyprland \
    pipewire pipewire-pulse pipewire-alsa wireplumber \
    bluez bluez-utils \
    foot waybar wofi grim slurp wl-clipboard \
    brightnessctl pamixer ttf-noto-fonts \
    greetd greetd-tuigreet

log_info "Installing Ghostty terminal from AUR..."
yay -S --noconfirm ghostty

# Part 3: Install hyprpm and hyprbars

log_info "Installing hyprpm and hyprbars plugin..."
git clone https://github.com/hyprwm/hyprpm /tmp/hyprpm
cd /tmp/hyprpm
make all
sudo make install
cd ~

hyprpm add https://github.com/hyprwm/hyprland-plugins
hyprpm enable hyprbars
hyprpm update

# Part 4: System Configuration

log_info "Enabling essential services..."
sudo systemctl enable --now bluetooth
sudo systemctl enable greetd

# Part 5: Hyprland Configuration with hyprbars

log_info "Setting up Hyprland configuration with hyprbars..."
mkdir -p ~/.config/hypr
cat > ~/.config/hypr/hyprland.conf << 'HYPR_EOF'
# Monitor configuration
monitor=,preferred,auto,1

# Autostart
exec-once = waybar
exec-once = hyprpaper
exec-once = foot --server
exec-once = hyprpm reload -n

# Environment
env = XCURSOR_SIZE,24

# Input configuration
input {
    kb_layout = us
    follow_mouse = 1
    touchpad {
        natural_scroll = false
        tap-to-click = true
    }
}

# Window and workspace settings
general {
    gaps_in = 4
    gaps_out = 8
    border_size = 2
    col.active_border = rgb(FF90BC) rgb(5FBDFF) 45deg
    col.inactive_border = rgba(595959aa)
    layout = dwindle
}

decoration {
    rounding = 10
    active_opacity = 0.93
    inactive_opacity = 0.87
    blur {
        enabled = true
        size = 3
        passes = 1
    }
}

# hyprbars configuration
plugin = hyprbars

hyprbars {
    # Titlebar configuration
    bar_height = 28
    bar_precedence_over_border = true
    
    # Button styling
    bar_button_padding = 5
    bar_button_radius = 7
    bar_button_border_size = 0
    
    # Button colors
    bar_button_color_close = rgb(ff605c)
    bar_button_color_maximize = rgb(ffbd44)
    bar_button_color_minimize = rgb(00ca4e)
    
    # Button hover colors
    bar_button_color_close_hover = rgba(ff605c77)
    bar_button_color_maximize_hover = rgba(ffbd4477)
    bar_button_color_minimize_hover = rgba(00ca4e77)
    
    # Title styling
    bar_title_enabled = true
    bar_title_font = Noto Sans
    bar_title_size = 12
    bar_title_color = rgb(000000)
    
    # Bar styling
    bar_color = rgba(245,245,245,0.90)
    bar_border_size = 0
    bar_border_color = rgb(000000)
    
    # Button layout
    bar_buttons_alignment = left
}

# Keybindings (keeping your original binds)
$mainMod = SUPER
$terminal = foot
$altTerminal = ghostty
$fileManager = thunar
$menu = wofi --show drun

# Basic bindings
bind = $mainMod, Return, exec, $terminal
bind = $mainMod SHIFT, Return, exec, $altTerminal
bind = $mainMod SHIFT, C, killactive,
bind = $mainMod SHIFT, X, exit,
bind = $mainMod, F, togglefloating,
bind = $mainMod, Space, exec, $menu
bind = $mainMod, E, exec, $fileManager

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

# Workspace keys
bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
bind = $mainMod, 3, workspace, 3
bind = $mainMod, 4, workspace, 4

bind = $mainMod SHIFT, 1, movetoworkspace, 1
bind = $mainMod SHIFT, 2, movetoworkspace, 2
bind = $mainMod SHIFT, 3, movetoworkspace, 3
bind = $mainMod SHIFT, 4, movetoworkspace, 4

# Special keys for volume and brightness
bind = $mainMod, XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%+
bind = $mainMod, XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-
bind = $mainMod, XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle

bind = , XF86MonBrightnessUp, exec, brightnessctl s +5%
bind = , XF86MonBrightnessDown, exec, brightnessctl s 5%-

# Window management with mouse
bindm = $mainMod, mouse:272, movewindow
bindm = $mainMod, mouse:273, resizewindow

# Screenshots
bind = $mainMod, Print, exec, grim -g "$(slurp)" - | wl-copy
HYPR_EOF

# Part 6: Final Setup

log_info "Installing additional utilities..."
sudo pacman -S --noconfirm \
    thunar thunar-volman thunar-archive-plugin \
    gnome-keyring flatpak fastfetch

log_info "Setting up Flathub..."
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

log_success "Installation completed!"
log_info "Hyprland with hyprbars is ready!"
log_info "Please reboot to start using your new desktop environment."