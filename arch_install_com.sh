#!/bin/bash

# Arch Linux Complete Installation Script with Hyprland
# Combines base installation and Hyprland setup in a single script
# 
# Prerequisites:
# 1. Boot from Arch Linux Live ISO
# 2. Connect to internet (Ethernet or WiFi via iwctl)
# 2a. If via iwctl, do these steps:
# rfkill unblock all
# iwctl
# > station list
# > station wlan0 scan
# > station wlan0 get-networks
# > station wlan0 connect <SSID>
# > <enter passphrase>
# > exit
# 
# 3. Run this script as root

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
DISK="/dev/sda"  # Change if needed
HOSTNAME="Vendetta"
USERNAME="CyberQuasar"
TIMEZONE="Asia/Jakarta"
LOG_FILE="/tmp/arch_install.log"

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

run_as_user() {
    sudo -u "$USERNAME" bash -c "$@" | tee -a "$LOG_FILE"
}

check_command() {
    if ! command -v "$1" &>/dev/null; then
        log_error "$1 could not be found"
    fi
}

install_package() {
    if ! pacman -S --noconfirm --needed "$@"; then
        log_error "Failed to install packages: $*"
    fi
}

cleanup() {
    log_info "Cleaning up..."
    umount -R /mnt 2>/dev/null || true
    swapoff "${DISK}2" 2>/dev/null || true
    rm -f /tmp/arch_install.* 2>/dev/null || true
}

confirm_continue() {
    read -rp "Continue? (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] || { log_error "Installation cancelled"; }
}

# Initialize logging
: > "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

# Verify environment
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
fi

trap cleanup EXIT INT TERM

# Check if we're in chroot
if [[ "$(stat -c %d:%i /)" != "$(stat -c %d:%i /proc/1/root/.)" ]]; then
    trap cleanup EXIT INT TERM
    
    # Verify live environment
    if ! grep -q "Arch Linux" /etc/os-release; then
        log_error "Must run from Arch Linux Live ISO"
    fi

    # Verify internet
    if ! ping -c 3 archlinux.org &>/dev/null; then
        log_error "No internet connection detected"
    fi
    log_success "Internet connection verified"

    # Verify UEFI
    if [[ ! -d /sys/firmware/efi ]]; then
        log_warning "System is not booted in UEFI mode"
        confirm_continue
    fi

    # Disk confirmation
    log_warning "This will install to $DISK with:"
    echo "  - ${DISK}1 (EFI, 512MB)"
    echo "  - ${DISK}2 (swap, 4000MB)"
    echo "  - ${DISK}3 (root, remaining space)"
    echo ""
    lsblk "$DISK"
    confirm_continue

    # Partitioning
    log_info "Creating partitions..."
    (
    echo g;     # GPT table
    echo n;     # EFI
    echo 1;     # Partition 1
    echo ;      # Default start
    echo +512MB;
    echo t; echo 1; # Type EFI
    echo n;     # Swap
    echo 2;     # Partition 2
    echo ;      # Default start
    echo +4000MB;
    echo t; echo 2; echo 19; # Type swap
    echo n;     # Root
    echo 3;     # Partition 3
    echo ; echo ; # Remainder
    echo t; echo 3; echo 20; # Type Linux
    echo w;     # Write
    ) | fdisk "$DISK" || log_error "Partitioning failed"

    # Formatting
    log_info "Formatting partitions..."
    mkfs.fat -F32 "${DISK}1" || log_error "EFI format failed"
    mkswap "${DISK}2" || log_error "Swap creation failed"
    swapon "${DISK}2"
    mkfs.btrfs -f "${DISK}3" || log_error "Root format failed"

    # Mounting
    log_info "Mounting filesystems..."
    mount "${DISK}3" /mnt || log_error "Root mount failed"
    mkdir -p /mnt/boot/efi
    mount "${DISK}1" /mnt/boot/efi || log_error "EFI mount failed"

    # Base installation
    log_info "Installing base system..."
    install_package archlinux-keyring
    pacstrap /mnt base linux linux-firmware sof-firmware base-devel \
        nano grub efibootmgr networkmanager iw wpa_supplicant \
        sudo git man-db man-pages texinfo || log_error "Base install failed"

    # Generate fstab
    genfstab -U /mnt > /mnt/etc/fstab || log_error "fstab generation failed"

    # Prepare post-install script in target system
    log_info "Preparing post-install configuration..."
    cat > /mnt/root/complete_install.sh <<POSTINSTALL
#!/bin/bash
set -euo pipefail

# Export variables for use in script
export TIMEZONE="$TIMEZONE"
export HOSTNAME="$HOSTNAME"
export USERNAME="$USERNAME"

# Basic setup
ln -sf /usr/share/zoneinfo/\$TIMEZONE /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Network configuration
echo "\$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<HOSTS_EOF
127.0.0.1    localhost
::1          localhost
127.0.1.1    \$HOSTNAME.localdomain \$HOSTNAME
HOSTS_EOF

# User setup
echo "Set root password:"
until passwd; do
    echo "Please try again"
done

useradd -mG wheel -s /bin/bash "\$USERNAME" || { echo "User creation failed"; exit 1; }
echo "Set password for \$USERNAME:"
until passwd "\$USERNAME"; do
    echo "Please try again"
done

# Sudo configuration
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Bootloader
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="Arch Linux" || { echo "GRUB install failed"; exit 1; }
echo "GRUB_TIMEOUT=0" >> /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg || { echo "GRUB config failed"; exit 1; }

# System services
systemctl enable NetworkManager || { echo "NetworkManager enable failed"; exit 1; }

# Hyprland installation
pacman -Syu --noconfirm || { echo "System update failed"; exit 1; }

# Install dependencies
pacman -S --noconfirm --needed git cmake meson gcc cpio \
    wayland wayland-protocols libxkbcommon xorg-xwayland \
    mesa libva-intel-driver intel-media-driver libva-utils \
    hyprland hyprpaper xdg-desktop-portal-hyprland \
    pipewire pipewire-pulse pipewire-alsa wireplumber \
    bluez bluez-utils foot waybar wofi grim slurp \
    wl-clipboard brightnessctl pamixer ttf-noto-fonts \
    greetd greetd-tuigreet thunar thunar-volman \
    thunar-archive-plugin gnome-keyring flatpak \
    fastfetch python python-pip openssh syncthing || { echo "Package install failed"; exit 1; }

# AUR helper (yay)
sudo -u "\$USERNAME" bash <<USEREOF
set -euo pipefail
cd /tmp
git clone https://aur.archlinux.org/yay.git || { echo "Yay clone failed"; exit 1; }
cd yay
makepkg -si --needed || { echo "Yay build failed"; exit 1; }
cd ~
USEREOF

# Install AUR packages
sudo -u "\$USERNAME" bash <<USEREOF
set -euo pipefail
echo "2" | yay -S --noconfirm ghostty-git || { echo "Ghostty install failed"; exit 1; }
echo "2" | yay -S --noconfirm hyprbars-hyprland-git || { echo "Hyprbars install failed"; exit 1; }
yay -S --noconfirm ttf-san-francisco-pro || { echo "SF Pro font install failed"; exit 1; }
USEREOF

# Install bpytop
python -m pip install psutil || { echo "psutil install failed"; exit 1; }
sudo -u "\$USERNAME" bash <<USEREOF
set -euo pipefail
cd /tmp
git clone https://github.com/aristocratos/bpytop.git || { echo "bpytop clone failed"; exit 1; }
cd bpytop
sudo make install || { echo "bpytop install failed"; exit 1; }
cd ~
rm -rf /tmp/bpytop
USEREOF

# Flatpak setup
sudo -u "\$USERNAME" flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || { echo "Flathub add failed"; exit 1; }

# Install Flatpak apps
sudo -u "\$USERNAME" bash <<USEREOF
set -euo pipefail
flatpak install -y flathub com.brave.Browser || { echo "Brave install failed"; exit 1; }
flatpak install -y flathub com.bitwarden.desktop || { echo "Bitwarden install failed"; exit 1; }
flatpak install -y flathub org.localsend.localsend || { echo "LocalSend install failed"; exit 1; }
USEREOF

# Create config directories
sudo -u "\$USERNAME" mkdir -p "/home/\$USERNAME/.config/hypr" || { echo "Config dir creation failed"; exit 1; }
sudo -u "\$USERNAME" mkdir -p "/home/\$USERNAME/.config/foot" || { echo "Foot config dir creation failed"; exit 1; }
sudo -u "\$USERNAME" mkdir -p "/home/\$USERNAME/.config/ghostty" || { echo "Ghostty config dir creation failed"; exit 1; }
sudo -u "\$USERNAME" mkdir -p "/home/\$USERNAME/Pictures" || { echo "Pictures dir creation failed"; exit 1; }

# Download wallpaper
sudo -u "\$USERNAME" curl -o "/home/\$USERNAME/Pictures/wallpaper.jpg" "https://images.pexels.com/photos/1169754/pexels-photo-1169754.jpeg" || { echo "Wallpaper download failed"; exit 1; }

# Hyprland configuration
cat > "/home/\$USERNAME/.config/hypr/hyprland.conf" <<'HYPR_EOF'
# Monitor configuration
monitor=,preferred,auto,1

# Autostart
exec-once = waybar
exec-once = hyprpaper
exec-once = foot --server

# Environment
env = XCURSOR_SIZE,24
env = HYPRCURSOR_SIZE,24

# Input configuration
input {
    kb_layout = us
    kb_variant = 
    kb_model = 
    kb_options = 
    kb_rules = 
    follow_mouse = 1
    sensitivity = 0
    accel_profile = flat
    touchpad {
        natural_scroll = false
    }
}

# General settings (Look and Feel)
general {
    gaps_in = 4
    gaps_out = 8
    border_size = 2
    col.active_border = rgb(FF90BC) rgb(5FBDFF) 45deg
    col.inactive_border = rgba(595959aa)
    resize_on_border = false
    allow_tearing = false
    layout = dwindle
}

# Decoration settings
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
        new_optimizations = true
        ignore_opacity = false
        vibrancy = 0.25
    }
}

# Animation settings
animations {
    enabled = true
    bezier = myBezier, 0.05, 0.9, 0.1, 1.05
    animation = windows, 1, 3, myBezier
    animation = windowsOut, 1, 5, default, popin 80%
    animation = border, 1, 10, default
    animation = fade, 1, 5, default
    animation = workspaces, 1, 6, default
}

# Layout settings
dwindle {
    pseudotile = true
    preserve_split = true
}

master {
    new_is_master = true
}

# Gestures
gestures {
    workspace_swipe = true
    workspace_swipe_fingers = 3
}

# Window rules
windowrule = suppressevent maximize, class:.*
windowrule = nofocus,class:^\$,title:^\$,xwayland:1,floating:1,fullscreen:0,pinned:0
windowrule = float, ^(pavucontrol)\$
windowrule = float, ^(file-roller)\$
windowrulev2 = opaque, class:^(ghostty)\$

# Keybindings
\$mainMod = SUPER
\$terminal = ghostty
\$foot = foot
\$fileManager = thunar
\$menu = wofi --show drun

# Basic bindings
bind = \$mainMod, Return, exec, \$foot
bind = \$mainMod SHIFT, Return, exec, \$terminal
bind = \$mainMod SHIFT, C, killactive,
bind = \$mainMod SHIFT, X, exit,
bind = \$mainMod, F, togglefloating,
bind = \$mainMod, Space, exec, \$menu
bind = \$mainMod, E, exec, \$fileManager

# Focus movement
bind = \$mainMod, left, movefocus, l
bind = \$mainMod, right, movefocus, r
bind = \$mainMod, up, movefocus, u
bind = \$mainMod, down, movefocus, d

# Move windows
bind = \$mainMod SHIFT, left, movewindow, l
bind = \$mainMod SHIFT, right, movewindow, r
bind = \$mainMod SHIFT, up, movewindow, u
bind = \$mainMod SHIFT, down, movewindow, d

# Workspace keys (4 workspaces)
bind = \$mainMod, 1, workspace, 1
bind = \$mainMod, 2, workspace, 2
bind = \$mainMod, 3, workspace, 3
bind = \$mainMod, 4, workspace, 4

bind = \$mainMod SHIFT, 1, movetoworkspace, 1
bind = \$mainMod SHIFT, 2, movetoworkspace, 2
bind = \$mainMod SHIFT, 3, movetoworkspace, 3
bind = \$mainMod SHIFT, 4, movetoworkspace, 4

# Special keys for volume and brightness
bind = \$mainMod, XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%+
bind = \$mainMod, XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-
bind = \$mainMod, XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle

bind = , XF86MonBrightnessUp, exec, brightnessctl s +5%
bind = , XF86MonBrightnessDown, exec, brightnessctl s 5%-

# Move windows by holding Super (MOD) + Left Mouse Button (LMB)
bindm = \$mainMod, mouse:272, movewindow

# Resize windows by holding Super (MOD) + Right Mouse Button (RMB)
bindm = \$mainMod, mouse:273, resizewindow

# Screenshots
bind = \$mainMod, Print, exec, grim -g "\$(slurp)" - | wl-copy

# Plugin hyprbars
plugin = hyprbars

hyprbars {
    height = 28
    corners = 10
    background-color = rgba(245,245,245,0.90)
    font = "San Francisco:style=Regular:pixelsize=16"
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

# Hyprpaper configuration
cat > "/home/\$USERNAME/.config/hypr/hyprpaper.conf" <<'PAPER_EOF'
preload = ~/Pictures/wallpaper.jpg
wallpaper = ,~/Pictures/wallpaper.jpg
PAPER_EOF

# Foot terminal configuration
cat > "/home/\$USERNAME/.config/foot/foot.ini" <<'FOOT_EOF'
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

# Ghostty terminal configuration
cat > "/home/\$USERNAME/.config/ghostty/config" <<'GHOSTTY_EOF'
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

# Wayland session file
mkdir -p /usr/share/wayland-sessions
cat > /usr/share/wayland-sessions/hyprland.desktop <<'SESSION_EOF'
[Desktop Entry]
Name=Hyprland
Comment=A dynamic tiling Wayland compositor based on wlroots
Exec=Hyprland
Type=Application
SESSION_EOF

# Configure greetd
cat > /etc/greetd/config.toml <<'GREETD_EOF'
[terminal]
vt = 1

[default_session]
command = "tuigreet --cmd Hyprland"
user = "greeter"
GREETD_EOF

# Set permissions
chown -R "\$USERNAME:\$USERNAME" "/home/\$USERNAME" || { echo "Permission set failed"; exit 1; }

# Enable services
systemctl enable --now bluetooth || { echo "Bluetooth enable failed"; exit 1; }
systemctl enable greetd || { echo "Greetd enable failed"; exit 1; }

echo "Installation complete inside chroot"
POSTINSTALL

    chmod +x /mnt/root/complete_install.sh

    # Run the complete installation in chroot
    log_info "Starting complete system configuration..."
    if ! arch-chroot /mnt /root/complete_install.sh; then
        log_error "Chroot configuration failed"
        exit 1
    fi

    # Successful completion message
    echo -e "\n${GREEN}=== INSTALLATION COMPLETED SUCCESSFULLY ===${NC}"
    log_info "System will automatically reboot in 5 seconds..."
    log_info "Press ${RED}Ctrl+C${NC} to cancel"
    
    # Visual countdown
    for i in {5..1}; do
        echo -ne "${YELLOW}Rebooting in ${i} seconds...${NC}\r"
        sleep 1
    done
    
    log_info "Rebooting now..."
    reboot
fi
