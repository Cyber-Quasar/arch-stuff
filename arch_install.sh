#!/bin/bash

# Arch Linux Base Installation Script
# 
# Prerequisites before running this script:
# 1. Boot from Arch Linux Live ISO
# 2. Connect to internet:
#    - Ethernet: should work automatically
#    - WiFi: use `iwctl` to connect
# 3. Partition your disk with cfdisk:
#    cfdisk /dev/sda
#    Create: sda1 (EFI, 512 MiB), sda2 (swap, 4 GiB), sda3 (rest, root)
# 4. Then run this script

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
if ! grep -q "Arch Linux" /etc/os-release; then
    log_error "This script should be run from an Arch Linux Live ISO"
    exit 1
fi

# Check internet connectivity
log_info "Checking internet connectivity..."
if ! ping -c 3 archlinux.org &>/dev/null; then
    log_error "No internet connection. Please connect to network first."
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
log_info "Formatting ${DISK}1 as FAT32..."
mkfs.fat -F32 ${DISK}1 && log_success "EFI partition formatted" || { log_error "Failed to format EFI partition"; exit 1; }

log_info "Creating and enabling swap on ${DISK}2..."
mkswap ${DISK}2 && log_success "Swap created" || { log_error "Failed to create swap"; exit 1; }
swapon ${DISK}2 && log_success "Swap enabled" || { log_error "Failed to enable swap"; exit 1; }

log_info "Formatting ${DISK}3 as Btrfs..."
mkfs.btrfs ${DISK}3 && log_success "Root partition formatted" || { log_error "Failed to format root partition"; exit 1; }

log_info "Mounting filesystems..."
log_info "Mounting root partition..."
mount ${DISK}3 /mnt && log_success "Root partition mounted" || { log_error "Failed to mount root partition"; exit 1; }

log_info "Creating EFI directory..."
mkdir -p /mnt/boot/efi && log_success "EFI directory created" || { log_error "Failed to create EFI directory"; exit 1; }

log_info "Mounting EFI partition..."
mount ${DISK}1 /mnt/boot/efi && log_success "EFI partition mounted" || { log_error "Failed to mount EFI partition"; exit 1; }

log_info "Verifying mounts..."
df -h | grep /mnt

log_info "Installing base system..."
log_info "This may take several minutes depending on your internet speed..."
if pacstrap /mnt base linux linux-firmware sof-firmware base-devel nano grub efibootmgr networkmanager \
iw wpa_supplicant dhcpcd net-tools sudo dosfstools ntfs-3g e2fsprogs exfatprogs git man-db man-pages \
texinfo; then
    log_success "Base system installed successfully"
else
    log_error "Failed to install base system"
    log_info "Check your internet connection and try again"
    exit 1
fi

log_info "Generating fstab..."
if genfstab -U /mnt > /mnt/etc/fstab; then
    log_success "fstab generated successfully"
    log_info "Generated fstab contents:"
    cat /mnt/etc/fstab
else
    log_error "Failed to generate fstab"
    exit 1
fi

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
echo "Vendetta" > /etc/hostname

# Configure hosts file
cat > /etc/hosts << 'HOSTS_EOF'
127.0.0.1    localhost
::1          localhost
127.0.1.1    Vendetta.localdomain Vendetta
HOSTS_EOF

# Set root password
echo "Please set root password:"
passwd

# Create user
useradd -mG wheel -s /bin/bash CyberQuasar
echo "Please set password for CyberQuasar:"
passwd CyberQuasar

# Configure sudo
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Install and configure GRUB
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Arch
grub-mkconfig -o /boot/grub/grub.cfg

# Enable essential services
systemctl enable NetworkManager
systemctl enable systemd-timesyncd

echo "Base system configuration completed!"
EOF

chmod +x /mnt/configure_system.sh
log_info "Running chroot configuration..."
if arch-chroot /mnt /configure_system.sh; then
    log_success "Chroot configuration completed successfully"
else
    log_error "Chroot configuration failed"
    exit 1
fi
rm /mnt/configure_system.sh

log_success "Base installation completed!"

log_info "Unmounting filesystems..."
log_info "Turning off swap..."
if swapoff ${DISK}2; then
    log_success "Swap turned off successfully"
else
    log_warning "Failed to turn off swap (may not be active)"
fi

log_info "Unmounting /mnt/boot/efi..."
if umount /mnt/boot/efi; then
    log_success "EFI partition unmounted"
else
    log_warning "Failed to unmount EFI partition (may already be unmounted)"
fi

log_info "Unmounting /mnt..."
if umount /mnt; then
    log_success "Root partition unmounted"
else
    log_error "Failed to unmount root partition"
    log_info "Trying forced unmount..."
    umount -f /mnt || log_warning "Forced unmount also failed"
fi

log_info "Checking if any mounts remain..."
if mount | grep -q "/mnt"; then
    log_warning "Some mounts still active:"
    mount | grep "/mnt"
else
    log_success "All mounts successfully removed"
fi

log_success "Installation script completed!"
echo ""
log_info "Next steps:"
echo "1. Remove the USB drive"
echo "2. Reboot your system"
echo "3. Log in as ${USERNAME}"
echo "4. Download post-install script:"
echo "   curl -o post_install.sh https://raw.githubusercontent.com/Cyber-Quasar/arch-stuff/main/post_install.sh"
echo "5. Run: chmod +x post_install.sh && ./post_install.sh"
echo "6. Reboot again to enjoy your new Hyprland desktop!"