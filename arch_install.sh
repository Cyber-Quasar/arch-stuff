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
# > sttaion list
# > station wlan0 scan
# > station wlan0 get-networks
# > sttaion wlan0 connect <SSID>
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
}

run_as_user() {
    sudo -u "$USERNAME" bash -c "$@" | tee -a "$LOG_FILE"
}

check_command() {
    if ! command -v "$1" &>/dev/null; then
        log_error "$1 could not be found"
        exit 1
    fi
}

install_package() {
    if ! pacman -S --noconfirm --needed "$@"; then
        log_error "Failed to install packages: $*"
        exit 1
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
    [[ $REPLY =~ ^[Yy]$ ]] || { log_error "Installation cancelled"; exit 1; }
}

# Initialize logging
: > "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

# Verify environment
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

trap cleanup EXIT INT TERM

# Check if we're in chroot
if [[ "$(stat -c %d:%i /)" != "$(stat -c %d:%i /proc/1/root/.)" ]]; then
    log_info "Starting Arch Linux base installation..."
    
    # Verify live environment
    if ! grep -q "Arch Linux" /etc/os-release; then
        log_error "Must run from Arch Linux Live ISO"
        exit 1
    fi

    # Verify internet
    if ! ping -c 3 archlinux.org &>/dev/null; then
        log_error "No internet connection detected"
        exit 1
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
    ) | fdisk "$DISK" || { log_error "Partitioning failed"; exit 1; }

    # Formatting
    log_info "Formatting partitions..."
    mkfs.fat -F32 "${DISK}1" || { log_error "EFI format failed"; exit 1; }
    mkswap "${DISK}2" || { log_error "Swap creation failed"; exit 1; }
    swapon "${DISK}2"
    mkfs.btrfs -f "${DISK}3" || { log_error "Root format failed"; exit 1; }

    # Mounting
    log_info "Mounting filesystems..."
    mount "${DISK}3" /mnt || { log_error "Root mount failed"; exit 1; }
    mkdir -p /mnt/boot/efi
    mount "${DISK}1" /mnt/boot/efi || { log_error "EFI mount failed"; exit 1; }

    # Base installation
    log_info "Installing base system..."
    install_package archlinux-keyring
    pacstrap /mnt base linux linux-firmware sof-firmware base-devel \
        nano grub efibootmgr networkmanager iw wpa_supplicant \
        sudo git man-db man-pages texinfo || { log_error "Base install failed"; exit 1; }

    # Generate fstab
    genfstab -U /mnt > /mnt/etc/fstab || { log_error "fstab generation failed"; exit 1; }

    # Chroot configuration
    log_info "Configuring base system..."
    arch-chroot /mnt bash <<EOF || { log_error "Chroot configuration failed"; exit 1; }
#!/bin/bash
set -euo pipefail

# Basic setup
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Network configuration
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<HOSTS_EOF
127.0.0.1    localhost
::1          localhost
127.0.1.1    $HOSTNAME.localdomain $HOSTNAME
HOSTS_EOF

# User setup
echo "Set root password:"
until passwd; do
    echo "Please try again"
done

useradd -mG wheel -s /bin/bash "$USERNAME" || { echo "User creation failed"; exit 1; }
echo "Set password for $USERNAME:"
until passwd "$USERNAME"; do
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
    fastfetch bpytop || { echo "Package install failed"; exit 1; }

# AUR helper
sudo -u "$USERNAME" bash <<USEREOF
set -euo pipefail
git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin || { echo "Yay clone failed"; exit 1; }
cd /tmp/yay-bin
makepkg -si --noconfirm || { echo "Yay build failed"; exit 1; }
cd ~
USEREOF

# Ghostty terminal
sudo -u "$USERNAME" yay -S --noconfirm ghostty || { echo "Ghostty install failed"; exit 1; }

# Hyprland plugins
git clone https://github.com/hyprwm/hyprpm /tmp/hyprpm || { echo "Hyprpm clone failed"; exit 1; }
cd /tmp/hyprpm
make all || { echo "Hyprpm build failed"; exit 1; }
make install || { echo "Hyprpm install failed"; exit 1; }
cd ~

sudo -u "$USERNAME" hyprpm add https://github.com/hyprwm/hyprland-plugins || { echo "Plugin add failed"; exit 1; }
sudo -u "$USERNAME" hyprpm enable hyprbars || { echo "Hyprbars enable failed"; exit 1; }
sudo -u "$USERNAME" hyprpm update || { echo "Hyprpm update failed"; exit 1; }

# Flatpak setup
sudo -u "$USERNAME" flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || { echo "Flathub add failed"; exit 1; }

# Hyprland configuration
sudo -u "$USERNAME" mkdir -p "/home/$USERNAME/.config/hypr" || { echo "Config dir creation failed"; exit 1; }
cat > "/home/$USERNAME/.config/hypr/hyprland.conf" <<'HYPR_EOF'
# [Previous Hyprland config content...]
HYPR_EOF

# Set permissions
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.config" || { echo "Permission set failed"; exit 1; }

# Enable services
systemctl enable --now bluetooth || { echo "Bluetooth enable failed"; exit 1; }
systemctl enable greetd || { echo "Greetd enable failed"; exit 1; }

echo "Installation complete inside chroot"
EOF

    log_success "Base installation complete!"
    log_info "Unmounting filesystems..."
    umount -R /mnt

    # Enhanced reboot countdown
    echo -e "\n${GREEN}=== Installation Complete ==="
    log_info "System will automatically reboot in 5 seconds..."
    log_info "Press ${RED}Ctrl+C${NC} to cancel"
    echo -ne "${YELLOW}Rebooting in:${NC} "
    for i in {5..1}; do
        echo -ne "${i} "
        sleep 1
    done
    echo -e "\n"
    reboot
fi