#!/bin/bash

# Complete Arch Linux Installation Script with Hyprland and hyprbars
# Boot from Arch ISO, partition disk, connect to internet, then run this script

set -e

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
    [[ $REPLY =~ ^[Yy]$ ]] || { log_error "Installation cancelled"; exit 1; }
}

# Verify we're running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

# Check if we're in chroot (post-install phase)
if [[ "$(stat -c %d:%i /)" != "$(stat -c %d:%i /proc/1/root/.)" ]]; then
    log_info "Starting Arch Linux base installation..."
    
    # Verify live environment
    if ! grep -q "Arch Linux" /etc/os-release; then
        log_error "Run from Arch Linux Live ISO"
        exit 1
    fi

    # Verify internet
    if ! ping -c 3 archlinux.org &>/dev/null; then
        log_error "No internet connection"
        exit 1
    fi
    log_success "Internet connection verified"

    # Confirm disk layout
    log_warning "This will install to $DISK with:"
    echo "  - ${DISK}1 (EFI, 512 MiB)"
    echo "  - ${DISK}2 (swap, 4 GiB)"
    echo "  - ${DISK}3 (root, remaining space)"
    echo ""
    lsblk $DISK
    confirm_continue

    # Format partitions
    log_info "Formatting partitions..."
    mkfs.fat -F32 ${DISK}1
    mkswap ${DISK}2 && swapon ${DISK}2
    mkfs.btrfs ${DISK}3

    # Mount filesystems
    log_info "Mounting filesystems..."
    mount ${DISK}3 /mnt
    mkdir -p /mnt/boot/efi
    mount ${DISK}1 /mnt/boot/efi

    # Install base system
    log_info "Installing base system..."
    pacstrap /mnt base linux linux-firmware sof-firmware base-devel nano grub efibootmgr \
        networkmanager iw wpa_supplicant sudo git man-db man-pages texinfo

    # Generate fstab
    genfstab -U /mnt > /mnt/etc/fstab

    # Inject post-install script into new system
    log_info "Preparing post-install script..."
    cat > /mnt/root/hyprland_install.sh <<'POSTINSTALL'
#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# Run as user
run_as_user() {
    sudo -u $USERNAME bash <<EOF
$@
EOF
}

log_info "Starting Hyprland post-installation..."

# Install build tools
log_info "Installing build dependencies..."
pacman -S --noconfirm --needed git cmake meson gcc cpio

# Install yay
log_info "Installing yay AUR helper..."
run_as_user git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin
cd /tmp/yay-bin
run_as_user makepkg -si --noconfirm
cd ~

# Install core packages
log_info "Installing core packages..."
pacman -S --noconfirm \
    wayland wayland-protocols libxkbcommon xorg-xwayland \
    mesa libva-intel-driver intel-media-driver libva-utils \
    hyprland hyprpaper xdg-desktop-portal-hyprland \
    pipewire pipewire-pulse pipewire-alsa wireplumber \
    bluez bluez-utils \
    foot waybar wofi grim slurp wl-clipboard \
    brightnessctl pamixer ttf-noto-fonts \
    greetd greetd-tuigreet

# Install Ghostty
log_info "Installing Ghostty terminal..."
run_as_user yay -S --noconfirm ghostty

# Install hyprpm and hyprbars
log_info "Setting up hyprpm and hyprbars..."
git clone https://github.com/hyprwm/hyprpm /tmp/hyprpm
cd /tmp/hyprpm
make all
make install
cd ~

run_as_user hyprpm add https://github.com/hyprwm/hyprland-plugins
run_as_user hyprpm enable hyprbars
run_as_user hyprpm update

# Enable services
log_info "Enabling services..."
systemctl enable --now bluetooth
systemctl enable greetd

# Configure Hyprland
log_info "Configuring Hyprland..."
run_as_user mkdir -p /home/$USERNAME/.config/hypr
cat > /home/$USERNAME/.config/hypr/hyprland.conf << 'HYPR_EOF'
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

# Install additional utilities
log_info "Installing additional software..."
pacman -S --noconfirm \
    thunar thunar-volman thunar-archive-plugin \
    gnome-keyring flatpak fastfetch bpytop

# Setup Flathub
run_as_user flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# Set permissions
chown -R $USERNAME:$USERNAME /home/$USERNAME/.config

log_success "Installation completed!"
echo ""
log_info "To complete setup:"
log_info "1. Reboot your system"
log_info "2. Log in as $USERNAME"
log_info "3. Hyprland should start automatically through greetd"
POSTINSTALL

    # Make post-install script executable
    chmod +x /mnt/root/hyprland_install.sh

    # Chroot configuration
    log_info "Configuring base system..."
    arch-chroot /mnt bash <<EOF
# Set timezone and locale
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set hostname
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<HOSTS_EOF
127.0.0.1    localhost
::1          localhost
127.0.1.1    $HOSTNAME.localdomain $HOSTNAME
HOSTS_EOF

# Set root password
echo "Set root password:"
passwd

# Create user
useradd -mG wheel -s /bin/bash $USERNAME
echo "Set password for $USERNAME:"
passwd $USERNAME

# Configure sudo
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Install and configure GRUB
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Arch
echo "GRUB_TIMEOUT=1" >> /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# Enable services
systemctl enable NetworkManager

# Run post-install script after reboot
echo "#!/bin/bash" > /etc/profile.d/hyprland_install.sh
echo "if [[ \$(whoami) == \"$USERNAME\" && ! -f /tmp/hyprland_installed ]]; then" >> /etc/profile.d/hyprland_install.sh
echo "    sudo /root/hyprland_install.sh" >> /etc/profile.d/hyprland_install.sh
echo "    sudo touch /tmp/hyprland_installed" >> /etc/profile.d/hyprland_install.sh
echo "fi" >> /etc/profile.d/hyprland_install.sh
chmod +x /etc/profile.d/hyprland_install.sh
EOF

    log_success "Base installation complete!"
    log_info "Unmounting and preparing for reboot..."
    umount -R /mnt
    log_info "Please reboot into your new system and login as $USERNAME"
    log_info "The Hyprland installation will continue automatically after login"
    exit 0
else
    # If we're not in the live environment but the script is running, it's probably the post-install
    if [[ -f /root/hyprland_install.sh ]]; then
        /root/hyprland_install.sh
        rm -f /etc/profile.d/hyprland_install.sh
        exit 0
    else
        log_error "Post-install script not found. Something went wrong with the base installation."
        exit 1
    fi
fi
