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

# Step 1: Verify internet connection
log_info "Verifying internet connection..."
if ! ping -c 3 archlinux.org &>/dev/null; then
    log_error "No internet connection detected. Please connect to internet first."
fi
log_success "Internet connection verified"

# Step 2: Verify UEFI boot
if [[ ! -d /sys/firmware/efi ]]; then
    log_warning "System is not booted in UEFI mode"
    confirm_continue
fi

# Step 3: Disk confirmation
log_warning "This will ERASE ALL DATA on $DISK and create:"
echo "  - ${DISK}1 (EFI, 512MB)"
echo "  - ${DISK}2 (SWAP, 4GB)"
echo "  - ${DISK}3 (root, remaining space)"
echo ""
lsblk "$DISK" || log_error "Disk $DISK not found"
confirm_continue

# Step 4: Create partitions
log_info "Creating partitions..."
(
echo g          # Create GPT partition table
echo n          # New partition (EFI)
echo 1          # Partition number 1
echo            # Default start
echo +512M      # Size
echo n          # New partition (Swap)
echo 2          # Partition number 2
echo            # Default start
echo +4G        # Size
echo n          # New partition (Root)
echo 3          # Partition number 3
echo            # Default start
echo            # Use remaining space
echo t          # Change type
echo 1          # Select partition 1
echo 1          # EFI System
echo t          # Change type
echo 2          # Select partition 2
echo 19         # Linux swap
echo t          # Change type
echo 3          # Select partition 3
echo 20         # Linux filesystem
echo w          # Write changes
) | fdisk "$DISK" || log_error "Partitioning failed"

# Step 5: Format partitions
log_info "Formatting partitions..."
mkfs.fat -F32 "${DISK}1" || log_error "EFI partition formatting failed"
mkswap "${DISK}2" || log_error "Swap creation failed"
swapon "${DISK}2" || log_error "Swap activation failed"
mkfs.btrfs -f "${DISK}3" || log_error "Root partition formatting failed"
# Step 6: Mount filesystems
log_info "Mounting filesystems..."
mount "${DISK}3" /mnt || log_error "Root mount failed"
mkdir -p /mnt/boot/efi
mount "${DISK}1" /mnt/boot/efi || log_error "EFI mount failed"
# Note: swap is already activated with swapon, no need to mount

# Step 7: Update package database and install base system
log_info "Installing base system..."
pacstrap /mnt base linux linux-firmware sof-firmware base-devel \
    nano grub efibootmgr networkmanager iw wpa_supplicant \
    sudo git man-db man-pages texinfo || log_error "Base system installation failed"

# Step 8: Generate fstab
log_info "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab || log_error "fstab generation failed"

# Step 9: Create chroot configuration script
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

# Disable download timeout for pacman
echo "[INFO] Configuring pacman..."
sed -i '40i DisableDownloadTimeout' /etc/pacman.conf || { echo "[ERROR] Failed to configure pacman"; exit 1; }

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
pacman -Syu --noconfirm --disable-download-timeout

# Install core Wayland packages
pacman -S --noconfirm --needed --disable-download-timeout \
    wayland wayland-protocols libxkbcommon xorg-xwayland \
    mesa libva-intel-driver intel-media-driver libva-utils \
    hyprland hyprpaper xdg-desktop-portal-hyprland \
    pipewire pipewire-jack pipewire-pulse pipewire-alsa wireplumber \
    bluez bluez-utils

# Install applications
pacman -S --noconfirm --needed --disable-download-timeout \
    foot waybar wofi grim slurp wl-clipboard greetd greetd-tuigreet \
    brightnessctl pamixer ttf-noto-nerd dunst jq network-manager-applet \
    openssh syncthing thunar thunar-volman thunar-archive-plugin \
    thunar-media-tags-plugin gnome-keyring flatpak fastfetch \
    gnome-software gnome-packagekit timeshift sddm \
    ghostty bpytop python python-pip cpio cmake meson gcc blueman

echo "[INFO] Base installation completed successfully!"

# Download the post-reboot script from GitHub
echo "[INFO] Downloading post-reboot script..."
curl -L -o /home/$USERNAME/install-part2.sh "https://raw.githubusercontent.com/Cyber-Quasar/arch-stuff/refs/heads/main/install-part2.sh" || { echo "[ERROR] Failed to download post-reboot script"; exit 1; }
chmod +x /home/$USERNAME/install-part2.sh
chown $USERNAME:$USERNAME /home/$USERNAME/install-part2.sh

# Create Wayland session
mkdir -p /usr/share/wayland-sessions
cat > /usr/share/wayland-sessions/hyprland.desktop << 'SESSION_EOF'
[Desktop Entry]
Name=Hyprland
Comment=A dynamic tiling Wayland compositor
Exec=Hyprland
Type=Application
SESSION_EOF

# Install SDDM Astronaut Theme
echo "[INFO] Installing SDDM Astronaut Theme..."
if ! curl -fsSL https://raw.githubusercontent.com/keyitdev/sddm-astronaut-theme/master/setup.sh | bash; then
    echo "[ERROR] Failed to install SDDM Astronaut Theme"
    exit 1
fi

# Set Astronaut as default theme
echo "[Theme]
Current=astronaut" > /etc/sddm.conf.d/10-astronaut-theme.conf

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
systemctl disable sddm
systemctl enable greetd

# Download the post-reboot script from GitHub
echo "[INFO] Downloading post-reboot script..."
curl -L -o /home/$USERNAME/install-part2.sh "https://raw.githubusercontent.com/Cyber-Quasar/arch-stuff/refs/heads/main/install-part2.sh" || { echo "[ERROR] Failed to download post-reboot script"; exit 1; }
chmod +x /home/$USERNAME/install-part2.sh
chown $USERNAME:$USERNAME /home/$USERNAME/install-part2.sh

echo "[SUCCESS] Chroot configuration completed!"
echo "[INFO] The system will reboot automatically."
echo "[INFO] After reboot, login as $USERNAME and run: ./install-part2.sh"
CHROOT_SCRIPT

chmod +x /mnt/root/arch_install_chroot.sh

# Step 10: Enter chroot and run configuration
log_info "Entering chroot environment and running configuration..."
arch-chroot /mnt /root/arch_install_chroot.sh || log_error "Chroot configuration failed"

# Step 11: Cleanup and reboot
log_info "Installation completed! Preparing for reboot..."
log_success "After reboot:"
log_success "1. Login as $USERNAME with the password you set"
log_success "2. Run: rfkill unblock all"
log_success "3. Run: nmcli dev wifi connect <SSID> password <password>"
log_success "4. Run: ./install-part2.sh"
log_success "5. Enjoy your new Arch Linux + Hyprland system!"

echo ""
log_info "System will reboot in 10 seconds..."
log_info "Press Ctrl+C to cancel reboot"

for i in {10..1}; do
    echo -ne "${YELLOW}Rebooting in ${i} seconds...${NC}\r"
    sleep 1
done

umount -R /mnt || true
reboot
