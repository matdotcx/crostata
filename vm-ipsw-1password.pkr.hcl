# Variables - No defaults for security
variable "vm_name" {
  type        = string
  description = "Name of the VM to create"
  default     = "custom-vm"
}

variable "ssh_username" {
  type        = string
  description = "SSH username for the VM (from 1Password)"
  sensitive   = true
}

variable "ssh_password" {
  type        = string
  description = "SSH password for the VM (from 1Password)"
  sensitive   = true
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key content (from 1Password)"
  sensitive   = true
}

variable "ipsw_url" {
  type        = string
  description = "URL or path to macOS IPSW file"
  default     = "latest" # Downloads latest macOS automatically
  # Or use a specific URL:
  # default = "https://updates.cdn-apple.com/2025SpringFCS/fullrestores/082-16517/AACDDC33-9683-4431-98AF-F04EF7C15EE3/UniversalMac_15.4_24E248_Restore.ipsw"
  # Or use a local file:
  # default = "~/Downloads/UniversalMac_15.4_24E248_Restore.ipsw"
}

variable "cpu_count" {
  type        = number
  description = "Number of CPU cores"
  default     = 4
}

variable "memory_gb" {
  type        = number
  description = "Memory in GB"
  default     = 8
}

variable "disk_size_gb" {
  type        = number
  description = "Disk size in GB"
  default     = 50
}

# Packer configuration
packer {
  required_plugins {
    tart = {
      version = ">= 1.12.0"
      source  = "github.com/cirruslabs/tart"
    }
  }
}

# Source configuration - Using IPSW instead of base image
source "tart-cli" "custom_vm" {
  from_ipsw    = var.ipsw_url
  vm_name      = var.vm_name
  cpu_count    = var.cpu_count
  memory_gb    = var.memory_gb
  disk_size_gb = var.disk_size_gb

  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_timeout  = "300s"

  # Automated macOS setup from IPSW
  boot_command = [
    # Wait for boot
    "<wait60s><spacebar>",

    # Language selection
    "<wait5s><enter>",

    # Country/Region
    "<wait5s>united states<enter>",

    # Written and spoken languages
    "<wait5s><tab><spacebar>",

    # Accessibility
    "<wait5s><tab><spacebar>",

    # Data & Privacy
    "<wait10s><tab><spacebar>",

    # Migration Assistant
    "<wait5s><tab><tab><tab><spacebar>",

    # Sign in with Apple ID (skip)
    "<wait5s><tab><tab><spacebar>",

    # Terms and Conditions
    "<wait5s><tab><spacebar><wait5s><tab><spacebar>",

    # Create user account - using variables from 1Password
    "<wait5s>${var.ssh_username}<tab>",
    "${var.ssh_username}<tab>",
    "${var.ssh_password}<tab>",
    "${var.ssh_password}<tab>",
    "<tab><tab><spacebar>",

    # Analytics (skip)
    "<wait10s><tab><tab><tab><tab><spacebar>",

    # Screen Time (skip)
    "<wait5s><tab><spacebar>",

    # Siri (skip)
    "<wait5s><tab><tab><spacebar>",

    # Choose Look
    "<wait5s><tab><spacebar>",

    # Setup complete
    "<wait30s>"
  ]
}

# Build configuration
build {
  sources = ["source.tart-cli.custom_vm"]

  # Wait for system to settle after initial setup
  provisioner "shell" {
    inline = ["sleep 30"]
  }

  # Configure SSH key from 1Password
  provisioner "shell" {
    inline = [
      "mkdir -p ~/.ssh",
      "chmod 700 ~/.ssh",
      "echo '${var.ssh_public_key}' >> ~/.ssh/authorized_keys",
      "chmod 600 ~/.ssh/authorized_keys",
      "echo 'SSH key from 1Password configured successfully'"
    ]
  }

  # Enable SSH
  provisioner "shell" {
    inline = [
      "echo 'Enabling SSH...'",
      "sudo systemsetup -setremotelogin on",
      "sudo systemsetup -getremotelogin"
    ]
  }

  # Enable VNC/Screen Sharing
  provisioner "shell" {
    inline = [
      "echo 'Enabling Screen Sharing for VNC...'",
      "sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -activate -configure -access -on -users ${var.ssh_username} -privs -all -restart -agent -menu",
      "sudo defaults write /var/db/launchd.db/com.apple.launchd/overrides.plist com.apple.screensharing -dict Disabled -bool false",
      "sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist || true"
    ]
  }

  # System configurations
  provisioner "shell" {
    inline = [
      "echo 'Configuring system settings...'",

      # Disable spotlight indexing
      "sudo mdutil -a -i off",

      # Enable passwordless sudo
      "echo '${var.ssh_username} ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/${var.ssh_username}",

      # Disable screen saver
      "defaults -currentHost write com.apple.screensaver idleTime 0",

      # Disable sleep
      "sudo pmset -a sleep 0",
      "sudo pmset -a disksleep 0",
      "sudo pmset -a displaysleep 0",

      # Disable automatic updates
      "sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool NO",
      "sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool NO",
      "sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool NO",

      # Enable auto-login (optional - comment out if not desired)
      "sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser ${var.ssh_username}",

      "echo 'System configuration complete'"
    ]
  }

  # Final summary
  provisioner "shell" {
    inline = [
      "echo '==================================='",
      "echo 'VM setup complete!'",
      "echo 'Username: ${var.ssh_username}'",
      "echo 'SSH: Enabled with key authentication'",
      "echo 'VNC: Enabled via Screen Sharing'",
      "echo 'Auto-login: Enabled'",
      "echo 'Passwordless sudo: Enabled'",
      "echo '==================================='"
    ]
  }
}
