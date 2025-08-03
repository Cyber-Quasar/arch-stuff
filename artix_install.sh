#!/bin/bash

# Artix Linux + Hyprland Setup Script
# Based on your installation guide for Lenovo 110-14IBR with Dinit and macOS-style Hyprbars
# Run this script AFTER connecting to the internet via connmanctl

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration variables
DISK="/dev/sda"  # Change if needed
HOSTNAME="Vendetta"
USERNAME="CyberQuasar"
TIMEZONE="Asia/Jakarta"

# Helper functions
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
}

confirm_continue() {
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_error "Installation cancelled by user"
        exit 1
    fi
}

# Check if we're running in live environment
if [[ ! -f /etc/artix-release ]]; then
    log_error "This script should be run from an Artix Live ISO"
    exit 1
fi

# Check internet connectivity
log_info "Checking internet connectivity..."
if ! ping -c 3 archlinux.org &>/dev/null; then
    log_error "No internet connection. Please connect via connmanctl first."
    exit 1
fi
log_success "Internet connection verified"

# Confirm disk and settings
log_warning "This script will:"
echo "  - Format disk: $DISK"
echo "  - Set hostname: $HOSTNAME"
echo "  - Create user: $USERNAME"
echo "  - Set timezone: $TIMEZONE"
echo ""
log_warning "ALL DATA ON $DISK WILL BE DESTROYED!"
confirm_continue

# Part 1: Base Installation

log_info "Verifying disk partitions..."
log_info "Expected partitions:"
echo "  - ${DISK}1 (EFI, 512 MiB)"
echo "  - ${DISK}2 (swap, 4 GiB)" 
echo "  - ${DISK}3 (root, remaining space)"
echo ""
lsblk $DISK
echo ""
log_warning "Make sure you have partitioned $DISK correctly before continuing!"
confirm_continue

log_info "Formatting partitions..."
mkfs.fat -F32 ${DISK}1
mkswap ${DISK}2
swapon ${DISK}2
mkfs.btrfs ${DISK}3

log_info "Mounting filesystems..."
mount ${DISK}3 /mnt
mkdir -p /mnt/boot/efi
mount ${DISK}1 /mnt/boot/efi

log_info "Installing base system..."
basestrap /mnt base linux linux-firmware sof-firmware base-devel nano dinit elogind-dinit \
connman-dinit grub efibootmgr ntp ntp-dinit linux-base man-db man-pages texinfo iw \
wpa_supplicant networkmanager dhcpcd net-tools visudo dosfstools ntfs-3g e2fsprogs \
exfatprogs git

log_info "Generating fstab..."
fstabgen -U /mnt > /mnt/etc/fstab

log_info "Entering chroot and configuring system..."

# Create a temporary script to run in chroot
cat > /mnt/configure_system.sh << 'EOF'
#!/bin/bash

# Set timezone and locale
ln -sf /usr/share/zoneinfo/Asia/Jakarta /etc/localtime
hwclock --systohc

# Configure locale
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set hostname
echo "CyberQuasar" > /etc/hostname

# Configure hosts file
cat > /etc/hosts << 'HOSTS_EOF'
127.0.0.1    localhost
::1          localhost
127.0.1.1    CyberQuasar.localdomain CyberQuasar
HOSTS_EOF

# Set root password
echo "Please set root password:"
passwd

# Create user
useradd -mG wheel -s /bin/bash XaveriusJuan
echo "Please set password for XaveriusJuan:"
passwd XaveriusJuan

# Configure sudo
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Install and configure GRUB
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ARTIX
grub-mkconfig -o /boot/grub/grub.cfg

# Enable essential services
ln -s /etc/dinit.d/connmand /etc/dinit.d/boot.d/
ln -s /etc/dinit.d/ntpd /etc/dinit.d/boot.d/
ln -s /etc/dinit.d/elogind /etc/dinit.d/boot.d/
ln -s /etc/dinit.d/wpa_supplicant /etc/dinit.d/boot.d/

echo "Base system configuration completed!"
EOF

chmod +x /mnt/configure_system.sh
artix-chroot /mnt /configure_system.sh
rm /mnt/configure_system.sh

log_success "Base installation completed!"
log_info "You can now reboot into your new system."
log_info "After reboot, run this script again with the --post-install flag to continue with Hyprland setup."

# Create post-install script
cat > /mnt/home/${USERNAME}/post_install.sh << 'POST_EOF'
#!/bin/bash

# Post-installation script for Hyprland setup

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

# Part 2: Install Wayland and Hyprland

log_info "Updating system..."
sudo pacman -Syu --noconfirm

log_info "Installing Wayland and dependencies..."
sudo pacman -S --noconfirm wayland wayland-protocols libxkbcommon xorg-xwayland

log_info "Installing Intel GPU drivers..."
sudo pacman -S --noconfirm mesa libva-intel-driver intel-media-driver libva-utils

log_info "Installing yay AUR helper..."
cd /tmp
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
cd ~

log_info "Installing Hyprland and accessories..."
yay -S --noconfirm hyprland-git hyprpaper-git xdg-desktop-portal-hyprland-git

log_info "Installing essential utilities..."
sudo pacman -S --noconfirm waybar wofi grim slurp wl-clipboard brightnessctl
yay -S --noconfirm foot pamixer ttf-noto-fonts hyprbars ttf-san-francisco-pro

log_info "Installing audio and bluetooth..."
sudo pacman -S --noconfirm pipewire pipewire-pulse pipewire-alsa wireplumber bluez bluez-utils bluez-dinit polkit

log_info "Enabling bluetooth service..."
sudo ln -s /etc/dinit.d/bluetoothd /etc/dinit.d/boot.d/

# Part 3: Configure Hyprland & Environment

log_info "Cloning dotfiles and configuring Hyprland..."
git clone https://github.com/woioeow/hyprland-dotfiles.git ~/hyprland-dotfiles
cp -r ~/hyprland-dotfiles/hypr_style1/* ~/.config/

log_info "Creating custom Hyprland configuration..."
cat > ~/.config/hypr/hyprland.conf << 'HYPR_EOF'
# Monitor configuration
monitor=,preferred,auto,1

# Autostart / Exec-once
exec-once = waybar
exec-once = mako
exec-once = hyprpaper
exec-once = foot --server

# Environment Variables
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
windowrule = nofocus,class:^$,title:^$,xwayland:1,floating:1,fullscreen:0,pinned:0
windowrule = float, ^(pavucontrol)$
windowrule = float, ^(file-roller)$
windowrulev2 = opaque, class:^(ghostty)$

# Keybindings
$mainMod = SUPER
$terminal = ghostty
$foot = foot
$fileManager = thunar
$menu = wofi --show drun

# Basic bindings
bind = $mainMod, Return, exec, $foot
bind = $mainMod SHIFT, Return, exec, $terminal
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

# Workspace keys (4 workspaces)
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

# Move windows by holding Super (MOD) + Left Mouse Button (LMB)
bindm = $mainMod, mouse:272, movewindow

# Resize windows by holding Super (MOD) + Right Mouse Button (RMB)
bindm = $mainMod, mouse:273, resizewindow

# Screenshots
bind = $mainMod, Print, exec, grim -g "$(slurp)" - | wl-copy

# Plugin hyprbars
plugin=hyprbars

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

log_info "Setting up wallpaper..."
mkdir -p ~/Pictures
curl -o ~/Pictures/wallpaper.jpg https://images.pexels.com/photos/1169754/pexels-photo-1169754.jpeg

cat > ~/.config/hypr/hyprpaper.conf << 'PAPER_EOF'
preload = ~/Pictures/wallpaper.jpg
wallpaper = ,~/Pictures/wallpaper.jpg
PAPER_EOF

# Part 4: Login Manager & Terminals

log_info "Setting up Wayland session file..."
sudo mkdir -p /usr/share/wayland-sessions
sudo tee /usr/share/wayland-sessions/hyprland.desktop > /dev/null << 'SESSION_EOF'
[Desktop Entry]
Name=Hyprland
Comment=A dynamic tiling Wayland compositor based on wlroots
Exec=Hyprland
Type=Application
SESSION_EOF

log_info "Installing and configuring greetd..."
sudo pacman -S --noconfirm greetd greetd-tuigreet greetd-dinit
sudo ln -s /etc/dinit.d/greetd /etc/dinit.d/boot.d/

sudo tee /etc/greetd/config.toml > /dev/null << 'GREETD_EOF'
[terminal]
vt = 1

[default_session]
command = "tuigreet --cmd Hyprland"
user = "greeter"
GREETD_EOF

log_info "Configuring Foot terminal..."
mkdir -p ~/.config/foot
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

log_info "Installing Ghostty terminal..."
sudo pacman -S --noconfirm cmake gcc pkg-config fontconfig freetype2 libxkbcommon pixman

cd /tmp
git clone https://github.com/mitchellh/ghostty.git
cd ghostty
meson setup build
ninja -C build
sudo ninja -C build install
cd ~

mkdir -p ~/.config/ghostty
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

# Part 5: Final Utilities

log_info "Installing extra software..."
sudo pacman -S --noconfirm thunar thunar-volman thunar-archive-plugin gnome-keyring

log_success "Installation completed!"
log_info "Reloading Hyprland configuration..."
if pgrep -x "Hyprland" > /dev/null; then
    hyprctl reload
fi

log_success "Setup completed successfully!"
log_info "Please reboot to start using your new Hyprland desktop environment."
log_info "After reboot, you can log in and Hyprland should start automatically."
log_warning "Remember to reboot or run 'hyprctl reload' after any Hyprland config changes."

POST_EOF

chmod +x /mnt/home/${USERNAME}/post_install.sh
chown 1000:1000 /mnt/home/${USERNAME}/post_install.sh

log_info "Unmounting filesystems..."
umount -R /mnt
swapoff ${DISK}2

log_success "Installation script completed!"
echo ""
log_info "Next steps:"
echo "1. Remove the USB drive"
echo "2. Reboot your system"
echo "3. Log in as ${USERNAME}"
echo "4. Run: ./post_install.sh"
echo "5. Reboot again to enjoy your new Hyprland desktop!"
echo ""
log_info "The post-install script will:"
echo "  - Install Hyprland and all dependencies"
echo "  - Clone and apply the dotfiles from woioeow/hyprland-dotfiles"
echo "  - Configure macOS-style hyprbars"
echo "  - Set up Ghostty and Foot terminals"
echo "  - Install greetd login manager"
echo "  - Install additional utilities"