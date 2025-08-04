#!/bin/bash

# Arch Linux Full Installation Script with Hyprland, ZRAM, Ghostty, and Dotfiles
# Author: CyberQuasar
# Features:
# - Full disk install with UEFI and Btrfs
# - Hyprland environment and dotfiles
# - ZRAM with 0.95× RAM and zstd
# - Ghostty + Pipewire via pacman

set -euo pipefail

# === Configurable Variables ===
DISK="/dev/sda"
HOSTNAME="Vendetta"
USERNAME="CyberQuasar"
TIMEZONE="Asia/Jakarta"
LOG_FILE="/tmp/arch_install.log"

# === Terminal Colors ===
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# === Logging Helpers ===
log_info()    { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; exit 1; }

# === Initial Checks ===
if [[ $EUID -ne 0 ]]; then log_error "Run as root."; fi

: > "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

if [[ "$(stat -c %d:%i /)" != "$(stat -c %d:%i /proc/1/root/.)" ]]; then
    grep -q "Arch Linux" /etc/os-release || log_error "Not Arch ISO."
    ping -c 1 archlinux.org &>/dev/null || log_error "No internet."
    log_success "Internet OK"

    if [[ ! -d /sys/firmware/efi ]]; then
        log_warning "Non-UEFI boot."
        read -rp "Continue anyway? (y/N): " yn
        [[ "$yn" =~ ^[Yy]$ ]] || exit 1
    fi

    log_warning "Wiping and installing on: $DISK"
    echo " - EFI (512MB) -> ${DISK}1"
    echo " - Root (rest) -> ${DISK}2"
    lsblk "$DISK"
    read -rp "Proceed? (y/N): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || exit 1

    # Partitioning
    log_info "Partitioning $DISK..."
    (
        echo g
        echo n; echo 1; echo; echo +512M
        echo t; echo 1; echo 1
        echo n; echo 2; echo; echo
        echo t; echo 2; echo 20
        echo w
    ) | fdisk "$DISK" || log_error "Partitioning failed"

    # Format and mount
    log_info "Formatting..."
    mkfs.fat -F32 "${DISK}1"
    mkfs.btrfs -f "${DISK}2"

    log_info "Mounting..."
    mount "${DISK}2" /mnt
    mkdir -p /mnt/boot/efi
    mount "${DISK}1" /mnt/boot/efi

    # Base installation
    log_info "Installing base system..."
    pacstrap /mnt base linux linux-firmware sof-firmware base-devel \
        nano grub efibootmgr networkmanager iw wpa_supplicant \
        sudo git man-db man-pages texinfo zram-generator || log_error "Pacstrap failed"

    genfstab -U /mnt > /mnt/etc/fstab

    # === Add dotfiles script ===
    cp /mnt/root/complete_install.sh /mnt/root/original_complete.sh 2>/dev/null || true
    install -Dm755 /mnt/root/original_complete.sh /mnt/root/post_install.sh

    # === Post-install script ===
    log_info "Creating integrated post-install script..."
    cat > /mnt/root/complete_install.sh <<EOF
#!/bin/bash
set -euo pipefail

# Set timezone and locale
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1    localhost
::1          localhost
127.0.1.1    $HOSTNAME.localdomain $HOSTNAME
HOSTS

# Set passwords
until passwd; do echo "Retry root password..."; done
useradd -mG wheel -s /bin/bash $USERNAME
until passwd $USERNAME; do echo "Retry user password..."; done
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Install and configure GRUB
log_info "Installing GRUB..."
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Arch
cat > /etc/default/grub <<GRUBCFG
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR=Arch
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""
GRUBCFG
grub-mkconfig -o /boot/grub/grub.cfg

# Enable services
systemctl enable NetworkManager bluetooth greetd

# Setup ZRAM
log_info "Setting up ZRAM..."
cat > /etc/systemd/zram-generator.conf <<ZRAMCONF
[zram0]
zram-size = ram * 0.95
compression-algorithm = zstd
ZRAMCONF

systemctl daemon-reexec
systemctl enable systemd-zram-setup@zram0.service

# Pull and run user's Hyprland + dotfiles setup
curl -o /root/post_install.sh https://raw.githubusercontent.com/Cyber-Quasar/arch-stuff/refs/heads/main/post_install.sh
chmod +x /root/post_install.sh
bash /root/post_install.sh

log_success "Post-install complete"
EOF

    chmod +x /mnt/root/complete_install.sh
    log_info "Running chroot post-install..."
    arch-chroot /mnt /root/complete_install.sh || log_error "Post-install failed"

    log_success "Installation complete! Rebooting in 5s..."
    sleep 5
    reboot
fi
