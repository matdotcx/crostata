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

variable "base_image" {
  type        = string
  description = "Base VM image to use"
  default     = "ghcr.io/cirruslabs/macos-sequoia-vanilla:latest"
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
      version = ">= 0.5.3"
      source  = "github.com/cirruslabs/tart"
    }
  }
}

# Source configuration
source "tart-cli" "custom_vm" {
  vm_base_name = var.base_image
  vm_name      = var.vm_name
  cpu_count    = var.cpu_count
  memory_gb    = var.memory_gb
  disk_size_gb = var.disk_size_gb
  
  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_timeout  = "120s"
  
  # Headless mode - no GUI window
  headless = true
}

# Build configuration
build {
  sources = ["source.tart-cli.custom_vm"]
  
  # Wait for system to settle
  provisioner "shell" {
    inline = ["sleep 10"]
  }
  
  # Configure SSH key
  provisioner "shell" {
    inline = [
      "mkdir -p ~/.ssh",
      "chmod 700 ~/.ssh",
      # SSH key comes from 1Password, not from a file
      "echo '${var.ssh_public_key}' >> ~/.ssh/authorized_keys",
      "chmod 600 ~/.ssh/authorized_keys",
      "echo 'SSH key configured successfully'"
    ]
  }
  
  # Enable VNC/Screen Sharing
  provisioner "shell" {
    inline = [
      "echo 'Enabling Screen Sharing...'",
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
      
      # Enable passwordless sudo for the user
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
      
      "echo 'System configuration complete'"
    ]
  }
  
  # Final cleanup
  provisioner "shell" {
    inline = [
      "echo 'VM setup complete!'",
      "echo 'Username: ${var.ssh_username}'",
      "echo 'SSH and VNC are enabled'"
    ]
  }
}
