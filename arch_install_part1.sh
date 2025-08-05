#!/bin/bash

# Arch Linux Installation Script - Part 1 (Live ISO)
# Run this after booting from Arch Linux Live ISO
# Make sure you have internet connection before running

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration variables
DISK="/dev/sda"
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
    exit 1
}

confirm_continue() {
    read -rp "Continue? (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] || { log_error "Installation cancelled"; }
}

# Verify we're running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
fi

# Verify we're in Arch Linux Live environment
if ! grep -q "Arch Linux" /etc/os-release; then
    log_error "Must run from Arch Linux Live ISO"
fi

log_info "Starting Arch Linux Installation - Part 1"

# Step 1: Setup USB tethering connection
log_info "Setting up USB tethering connection..."
log_info "Please connect your phone via USB and enable USB tethering/hotspot"
echo "Waiting for USB network interface..."

# Wait for USB network interface to appear
USB_INTERFACE=""
for i in {1..30}; do
    if ip link show | grep -E "(usb[0-9]|enp.*usb)" &>/dev/null; then
        USB_INTERFACE=$(ip link show | grep -E "(usb[0-9]|enp.*usb)" | head -1 | cut -d: -f2 | tr -d ' ')
        break
    fi
    echo "Waiting for USB interface... ($i/30)"
    sleep 2
done

if [[ -n "$USB_INTERFACE" ]]; then
    log_success "Found USB interface: $USB_INTERFACE"
    log_info "Starting DHCP client on $USB_INTERFACE..."
    
    # Bring up the interface
    ip link set "$USB_INTERFACE" up
    
    # Start DHCP client
    dhcpcd "$USB_INTERFACE" &
    DHCPCD_PID=$!
    
    # Wait for IP address
    log_info "Waiting for IP address..."
    for i in {1..20}; do
        if ip addr show "$USB_INTERFACE" | grep -q "inet.*scope global"; then
            IP_ADDR=$(ip addr show "$USB_INTERFACE" | grep "inet.*scope global" | awk '{print $2}')
            log_success "Got IP address: $IP_ADDR"
            break
        fi
        echo "Waiting for IP... ($i/20)"
        sleep 2
    done
else
    log_warning "No USB interface found. Trying alternative methods..."
    
    # Try to use NetworkManager if available
    if command -v nmcli &>/dev/null; then
        log_info "Attempting to use NetworkManager for USB tethering..."
        systemctl start NetworkManager
        sleep 3
        nmcli device status
    else
        log_error "No USB tethering interface found and NetworkManager not available."
        echo "Please ensure:"
        echo "1. Your phone is connected via USB"
        echo "2. USB tethering/hotspot is enabled on your phone"
        echo "3. Your phone is set to 'Transfer files' or 'PTP' mode"
        confirm_continue
    fi
fi

# Step 2: Verify internet connection
log_info "Verifying internet connection..."
if ! ping -c 3 archlinux.org &>/dev/null; then
    log_warning "Initial ping failed, trying alternative DNS..."
    if ! ping -c 3 8.8.8.8 &>/dev/null; then
        log_error "No internet connection detected. Please check your USB tethering setup."
        echo ""
        echo "Troubleshooting:"
        echo "1. Ensure USB tethering is enabled on your phone"
        echo "2. Try different USB cable or port"
        echo "3. Check phone's USB connection mode"
        echo "4. Some phones require enabling 'Developer Options' first"
        exit 1
    else
        log_warning "Can reach internet but DNS might be slow"
    fi
fi
log_success "Internet connection verified via USB tethering"

# Step 3: Verify UEFI boot
if [[ ! -d /sys/firmware/efi ]]; then
    log_warning "System is not booted in UEFI mode"
    confirm_continue
fi

# Step 4: Disk confirmation
log_warning "This will ERASE ALL DATA on $DISK and create:"
echo "  - ${DISK}1 (EFI, 512MB)"
echo "  - ${DISK}2 (root, remaining space)"
echo ""
lsblk "$DISK" || log_error "Disk $DISK not found"
confirm_continue

# Step 5: Create partitions
log_info "Creating partitions..."
(
echo g     # Create GPT partition table
echo n     # New partition (EFI)
echo 1     # Partition number 1
echo       # Default start
echo +512MB # Size
echo t     # Change type
echo 1     # EFI System
echo n     # New partition (Root)
echo 2     # Partition number 2
echo       # Default start
echo       # Use remaining space
echo t     # Change type
echo 2     # Partition number
echo 20    # Linux filesystem
echo w     # Write changes
) | fdisk "$DISK" || log_error "Partitioning failed"

# Step 6: Format partitions
log_info "Formatting partitions..."
mkfs.fat -F32 "${DISK}1" || log_error "EFI partition formatting failed"
mkfs.btrfs -f "${DISK}2" || log_error "Root partition formatting failed"

# Step 7: Mount filesystems
log_info "Mounting filesystems..."
mount "${DISK}2" /mnt || log_error "Root mount failed"
mkdir -p /mnt/boot/efi
mount "${DISK}1" /mnt/boot/efi || log_error "EFI mount failed"

# Step 8: Update package database and install base system
log_info "Updating package database..."
pacman -Sy archlinux-keyring || log_error "Package database update failed"

log_info "Installing base system..."
pacstrap /mnt base linux linux-firmware sof-firmware base-devel \
    nano grub efibootmgr networkmanager iw wpa_supplicant \
    sudo git man-db man-pages texinfo || log_error "Base system installation failed"

# Step 9: Generate fstab
log_info "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab || log_error "fstab generation failed"

# Step 10: Create chroot configuration script
log_info "Creating chroot configuration script..."
cat > /mnt/root/arch_install_chroot.sh << 'CHROOT_SCRIPT'
#!/bin/bash

set -euo pipefail

# Configuration variables
HOSTNAME="Vendetta"
USERNAME="CyberQuasar"
TIMEZONE="Asia/Jakarta"

echo "[INFO] Starting chroot configuration..."

# Set timezone
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Configure locale
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set hostname
echo "$HOSTNAME" > /etc/hostname

# Configure hosts file
cat > /etc/hosts << EOF
127.0.0.1    localhost
::1          localhost
127.0.1.1    $HOSTNAME.localdomain $HOSTNAME
EOF

# Set root password
echo "Setting root password:"
until passwd; do
    echo "Please try again"
done

# Create user
useradd -mG wheel -s /bin/bash "$USERNAME"
echo "Setting password for $USERNAME:"
until passwd "$USERNAME"; do
    echo "Please try again"
done

# Configure sudo
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Install GRUB
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="Arch Linux"
echo "GRUB_TIMEOUT=0" >> /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# Enable NetworkManager
systemctl enable NetworkManager

# Install zram-generator
pacman -S --noconfirm zram-generator

# Configure ZRAM (0.95 × RAM with zstd compression)
cat > /etc/systemd/zram-generator.conf << EOF
[zram0]
zram-size = ram * 0.95
compression-algorithm = zstd
EOF

# Enable zram
systemctl enable systemd-zram-setup@zram0.service

# Update system
pacman -Syu --noconfirm

# Install core Wayland packages
pacman -S --noconfirm --needed \
    wayland wayland-protocols libxkbcommon xorg-xwayland \
    mesa libva-intel-driver intel-media-driver libva-utils \
    hyprland hyprpaper xdg-desktop-portal-hyprland \
    pipewire pipewire-jack pipewire-pulse pipewire-alsa wireplumber \
    bluez bluez-utils

# Install applications
pacman -S --noconfirm --needed \
    foot waybar wofi grim slurp wl-clipboard \
    brightnessctl pamixer ttf-noto-fonts greetd greetd-tuigreet \
    openssh syncthing thunar thunar-volman thunar-archive-plugin \
    thunar-media-tags-plugin gnome-keyring flatpak fastfetch \
    gnome-software gnome-software-packagekit-plugin \
    ghostty bpytop brave python python-pip cpio cmake meson gcc

echo "[INFO] Base installation completed successfully!"
echo "[INFO] Creating post-reboot script..."

# Create post-reboot script
cat > /home/$USERNAME/arch_install_part2.sh << 'POST_REBOOT_SCRIPT'
#!/bin/bash

# Arch Linux Installation Script - Part 2 (Post-Reboot)
# Run this after first boot into the new system

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

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

log_info "Starting Arch Linux Installation - Part 2"

# Install yay AUR helper
log_info "Installing yay AUR helper..."
cd /tmp
git clone https://aur.archlinux.org/yay.git || log_error "Failed to clone yay"
cd yay
makepkg -si --noconfirm --needed || log_error "Failed to build yay"
cd ~

# Install hyprbars plugin using hyprpm
log_info "Installing hyprbars plugin..."
hyprpm update || log_error "Failed to update hyprpm"
hyprpm add https://github.com/hyprwm/hyprland-plugins || log_error "Failed to add hyprland-plugins"
hyprpm enable hyprbars || log_error "Failed to enable hyprbars"

# Create config directories
log_info "Creating configuration directories..."
mkdir -p ~/.config/hypr ~/.config/foot ~/.config/ghostty ~/Pictures

# Download wallpaper
log_info "Downloading wallpaper..."
curl -o ~/Pictures/wallpaper.jpg "https://images.pexels.com/photos/1169754/pexels-photo-1169754.jpeg" || log_error "Failed to download wallpaper"

# Setup Flatpak
log_info "Setting up Flatpak..."
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || log_error "Failed to add Flathub"

# Install Flatpak applications
log_info "Installing Flatpak applications..."
flatpak install -y flathub com.bitwarden.desktop || log_error "Failed to install Bitwarden"
flatpak install -y flathub org.localsend.localsend || log_error "Failed to install LocalSend"

# Create Hyprland configuration
log_info "Creating Hyprland configuration..."
cat > ~/.config/hypr/hyprland.conf << 'HYPR_EOF'
# Monitor configuration
monitor=,preferred,auto,1

# Autostart
exec-once = waybar
exec-once = hyprpaper
exec-once = hyprpm reload -n
exec-once = foot --server

# Environment
env = XCURSOR_SIZE,24
env = HYPRCURSOR_SIZE,24

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
windowrulev2 = opaque, class:^(ghostty)$

# Keybindings
$mainMod = SUPER
$terminal = ghostty
$foot = foot
$fileManager = thunar
$menu = wofi -i --show drun --allow-images -D key_expand=Tab

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

# Plugin hyprbars
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

# Create Hyprpaper configuration
log_info "Creating Hyprpaper configuration..."
cat > ~/.config/hypr/hyprpaper.conf << 'PAPER_EOF'
preload = ~/Pictures/wallpaper.jpg
wallpaper = ,~/Pictures/wallpaper.jpg
PAPER_EOF

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

log_success "Configuration completed successfully!"
log_info "You can now:"
log_info "- Use Super + Enter for Foot terminal"
log_info "- Use Super + Shift + Enter for Ghostty terminal"
log_info "- Use Super + Space for application launcher"
log_info "- Use Super + E for file manager"
log_info "- Use Super + Print for screenshots"

echo ""
log_success "Arch Linux with Hyprland installation completed!"
POST_REBOOT_SCRIPT

# Make post-reboot script executable
chmod +x /home/$USERNAME/arch_install_part2.sh
chown $USERNAME:$USERNAME /home/$USERNAME/arch_install_part2.sh

# Create Wayland session
mkdir -p /usr/share/wayland-sessions
cat > /usr/share/wayland-sessions/hyprland.desktop << 'SESSION_EOF'
[Desktop Entry]
Name=Hyprland
Comment=A dynamic tiling Wayland compositor
Exec=Hyprland
Type=Application
SESSION_EOF

# Configure greetd
cat > /etc/greetd/config.toml << 'GREETD_EOF'
[terminal]
vt = 1

[default_session]
command = "tuigreet --cmd Hyprland"
user = "greeter"
GREETD_EOF

# Enable services
systemctl enable bluetooth
systemctl enable greetd

echo "[SUCCESS] Chroot configuration completed!"
echo "[INFO] The system will reboot automatically."
echo "[INFO] After reboot, login as $USERNAME and run: ./arch_install_part2.sh"
CHROOT_SCRIPT

chmod +x /mnt/root/arch_install_chroot.sh

# Step 11: Enter chroot and run configuration
log_info "Entering chroot environment and running configuration..."
arch-chroot /mnt /root/arch_install_chroot.sh || log_error "Chroot configuration failed"

# Step 12: Cleanup and reboot
log_info "Installation completed! Preparing for reboot..."
log_success "After reboot:"
log_success "1. Login as $USERNAME with the password you set"
log_success "2. Run: ./arch_install_part2.sh"
log_success "3. Enjoy your new Arch Linux + Hyprland system!"

echo ""
log_info "System will reboot in 10 seconds..."
log_info "Press Ctrl+C to cancel reboot"

for i in {10..1}; do
    echo -ne "${YELLOW}Rebooting in ${i} seconds...${NC}\r"
    sleep 1
done

# Stop dhcpcd if it was started
if [[ -n "$DHCPCD_PID" ]]; then
    kill $DHCPCD_PID 2>/dev/null || true
fi

umount -R /mnt || true
reboot