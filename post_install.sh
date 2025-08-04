#!/bin/bash

# Hyprland Post-Installation Configuration Script
# To be run after base Arch Linux installation
# Run as root on the new system

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
USERNAME="CyberQuasar"
LOG_FILE="/var/log/hyprland_postinstall.log"

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
    exit 1
}

run_as_user() {
    sudo -u "$USERNAME" bash -c "$@" | tee -a "$LOG_FILE"
}

check_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        log_error "Required command not found: $1"
    fi
}

install_package() {
    log_info "Installing packages: $*"
    if ! pacman -S --noconfirm --needed "$@"; then
        log_error "Failed to install packages: $*"
    fi
}

# Initialize logging
: > "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

# Verify environment
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
fi

if ! id -u "$USERNAME" >/dev/null 2>&1; then
    log_error "User $USERNAME does not exist"
fi

# Verify system is properly set up
check_command pacman
check_command git
check_command sudo

log_info "Starting Hyprland post-installation process"

# System update
log_info "Performing full system update"
install_package archlinux-keyring
pacman -Syu --noconfirm || log_error "System update failed"

# Install build tools
log_info "Installing build dependencies"
install_package git cmake meson gcc cpio

# Install yay AUR helper
log_info "Installing yay AUR helper"
run_as_user "mkdir -p /tmp/yay-install && git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-install/yay-bin"
run_as_user "cd /tmp/yay-install/yay-bin && makepkg -si --noconfirm" || log_error "yay installation failed"

# Install core packages
log_info "Installing core Hyprland packages"
install_package \
    wayland wayland-protocols libxkbcommon xorg-xwayland \
    mesa libva-intel-driver intel-media-driver libva-utils \
    hyprland hyprpaper xdg-desktop-portal-hyprland \
    pipewire pipewire-pulse pipewire-alsa wireplumber \
    bluez bluez-utils \
    foot waybar wofi grim slurp wl-clipboard \
    brightnessctl pamixer ttf-noto-fonts \
    greetd greetd-tuigreet

# Install Ghostty terminal
log_info "Installing Ghostty terminal"
run_as_user "yay -S --noconfirm ghostty" || log_warning "Ghostty installation failed - continuing anyway"

# Install hyprpm and hyprbars
log_info "Setting up hyprpm and hyprbars"
temp_dir=$(mktemp -d)
git clone https://github.com/hyprwm/hyprpm "$temp_dir/hyprpm" || log_error "Failed to clone hyprpm"
cd "$temp_dir/hyprpm"
make all || log_error "hyprpm build failed"
make install || log_error "hyprpm installation failed"
cd ~

run_as_user "hyprpm add https://github.com/hyprwm/hyprland-plugins" || log_error "Failed to add hyprland plugins"
run_as_user "hyprpm enable hyprbars" || log_error "Failed to enable hyprbars"
run_as_user "hyprpm update" || log_error "Failed to update hyprpm"

# Enable services
log_info "Enabling system services"
systemctl enable --now bluetooth || log_warning "Failed to enable bluetooth - continuing anyway"
systemctl enable greetd || log_error "Failed to enable greetd"

# Configure Hyprland
log_info "Configuring Hyprland environment"
user_home="/home/$USERNAME"
config_dir="$user_home/.config/hypr"

if [[ ! -d "$config_dir" ]]; then
    run_as_user "mkdir -p '$config_dir'" || log_error "Failed to create config directory"
fi

# Create Hyprland configuration
cat > "/tmp/hyprland.conf" <<'HYPR_EOF'
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
        tap-to-click = false
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
    bar_height = 28
    bar_precedence_over_border = true
    bar_button_padding = 5
    bar_button_radius = 7
    bar_button_border_size = 0
    bar_button_color_close = rgb(ff605c)
    bar_button_color_maximize = rgb(ffbd44)
    bar_button_color_minimize = rgb(00ca4e)
    bar_button_color_close_hover = rgba(ff605c77)
    bar_button_color_maximize_hover = rgba(ffbd4477)
    bar_button_color_minimize_hover = rgba(00ca4e77)
    bar_title_enabled = true
    bar_title_font = Noto Sans
    bar_title_size = 12
    bar_title_color = rgb(000000)
    bar_color = rgba(245,245,245,0.90)
    bar_border_size = 0
    bar_buttons_alignment = left
}

# Keybindings
$mainMod = SUPER
$terminal = foot
$altTerminal = ghostty
$fileManager = thunar
$menu = wofi --show drun

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

# Special keys
bind = $mainMod, XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%+
bind = $mainMod, XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-
bind = $mainMod, XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
bind = , XF86MonBrightnessUp, exec, brightnessctl s +5%
bind = , XF86MonBrightnessDown, exec, brightnessctl s 5%-

# Mouse controls
bindm = $mainMod, mouse:272, movewindow
bindm = $mainMod, mouse:273, resizewindow

# Screenshots
bind = $mainMod, Print, exec, grim -g "$(slurp)" - | wl-copy
HYPR_EOF

# Move config to user directory
mv "/tmp/hyprland.conf" "$config_dir/hyprland.conf" || log_error "Failed to move config file"
chown -R "$USERNAME:$USERNAME" "$config_dir" || log_error "Failed to set config permissions"

# Install additional utilities
log_info "Installing additional software"
install_package \
    thunar thunar-volman thunar-archive-plugin \
    gnome-keyring flatpak fastfetch bpytop

# Setup Flathub
log_info "Configuring Flatpak"
run_as_user "flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo" || log_warning "Failed to add Flathub repository"

# Final permissions
log_info "Setting final permissions"
chown -R "$USERNAME:$USERNAME" "$user_home/.config" || log_error "Failed to set permissions on config directory"

log_success "Hyprland post-installation completed successfully!"
log_info "You can now log in as $USERNAME"
log_info "Hyprland will start automatically through greetd"
log_info "Installation log saved to $LOG_FILE"

# Reboot countdown
log_info "System will automatically reboot in 5 seconds..."
echo -n "Rebooting in: "
for i in {5..1}; do
    echo -n "$i "
    sleep 1
done
echo
log_info "Rebooting now..."
reboot

exit 0