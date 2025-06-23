# Variables - No defaults for security
variable "vm_name" {
  type        = string
  description = "Name of the VM to create"
  default     = "custom-vm"
}

variable "ssh_username" {
  type        = string
  description = "SSH username for the new user (from 1Password)"
  sensitive   = true
}

variable "ssh_password" {
  type        = string
  description = "SSH password for the new user (from 1Password)"
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

# Source configuration - connect with default admin/admin credentials
source "tart-cli" "custom_vm" {
  vm_base_name = var.base_image
  vm_name      = var.vm_name
  cpu_count    = var.cpu_count
  memory_gb    = var.memory_gb
  disk_size_gb = var.disk_size_gb
  
  # Use default credentials from vanilla image
  ssh_username = "admin"
  ssh_password = "admin"
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
  
  # Create new admin user with our credentials
  provisioner "shell" {
    inline = [
      "echo 'Creating new admin user: ${var.ssh_username}'",
      
      # Find next available UID (starting from 501)
      "NEXT_UID=$(dscl . -list /Users UniqueID | awk '{print $2}' | sort -n | tail -1)",
      "NEXT_UID=$((NEXT_UID + 1))",
      
      # Create the new user account
      "sudo dscl . -create /Users/${var.ssh_username}",
      "sudo dscl . -create /Users/${var.ssh_username} UserShell /bin/zsh",
      "sudo dscl . -create /Users/${var.ssh_username} RealName '${var.ssh_username}'",
      "sudo dscl . -create /Users/${var.ssh_username} UniqueID $NEXT_UID",
      "sudo dscl . -create /Users/${var.ssh_username} PrimaryGroupID 20",
      "sudo dscl . -create /Users/${var.ssh_username} NFSHomeDirectory /Users/${var.ssh_username}",
      
      # Set password
      "sudo dscl . -passwd /Users/${var.ssh_username} '${var.ssh_password}'",
      
      # Create home directory
      "sudo mkdir -p /Users/${var.ssh_username}",
      "sudo chown -R ${var.ssh_username}:staff /Users/${var.ssh_username}",
      
      # Add to admin group
      "sudo dscl . -append /Groups/admin GroupMembership ${var.ssh_username}",
      
      # Enable passwordless sudo for new user
      "echo '${var.ssh_username} ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/${var.ssh_username}",
      
      "echo 'New admin user created successfully'"
    ]
  }
  
  # Configure SSH keys for new user
  provisioner "shell" {
    inline = [
      "echo 'Setting up SSH keys for ${var.ssh_username}'",
      
      # Create .ssh directory for new user
      "sudo mkdir -p /Users/${var.ssh_username}/.ssh",
      "sudo chmod 700 /Users/${var.ssh_username}/.ssh",
      
      # Add SSH public key
      "echo '${var.ssh_public_key}' | sudo tee /Users/${var.ssh_username}/.ssh/authorized_keys",
      "sudo chmod 600 /Users/${var.ssh_username}/.ssh/authorized_keys",
      
      # Set ownership
      "sudo chown -R ${var.ssh_username}:staff /Users/${var.ssh_username}/.ssh",
      
      "echo 'SSH key configured for ${var.ssh_username}'"
    ]
  }
  
  # Enable SSH and VNC for new user
  provisioner "shell" {
    inline = [
      "echo 'Enabling remote access for ${var.ssh_username}'",
      
      # Enable SSH if not already enabled
      "sudo systemsetup -setremotelogin on || true",
      
      # Enable VNC/Screen Sharing for new user
      "sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -activate -configure -access -on -users ${var.ssh_username} -privs -all -restart -agent -menu",
      
      "echo 'Remote access enabled'"
    ]
  }
  
  # Test new user can connect and sudo
  provisioner "shell" {
    inline = [
      "echo 'Testing new user SSH access...'",
      
      # Verify our new user can sudo
      "sudo -u ${var.ssh_username} sudo echo 'New user sudo access verified'",
      
      # Create a flag file to indicate the new user is ready
      "sudo touch /tmp/new_user_ready",
      
      "echo 'New user is ready for connection'"
    ]
  }
  
  # Disconnect and reconnect as new user to delete admin
  provisioner "shell" {
    # Override connection to use new user credentials
    override = {
      tart-cli = {
        ssh_username = var.ssh_username
        ssh_password = var.ssh_password
      }
    }
    
    pause_before = "5s"  # Give system time to settle
    
    inline = [
      "echo 'Connected as new user: ${var.ssh_username}'",
      
      # Verify we're the new user
      "whoami",
      
      # Now we can delete the admin user
      "echo 'Removing default admin user...'",
      "sudo dscl . -delete /Users/admin",
      "sudo rm -rf /Users/admin",
      
      "echo 'Default admin user removed successfully'"
    ]
  }
  
  # System configurations (running as new user)
  provisioner "shell" {
    override = {
      tart-cli = {
        ssh_username = var.ssh_username
        ssh_password = var.ssh_password
      }
    }
    
    inline = [
      "echo 'Configuring system settings...'",
      
      # Disable spotlight indexing
      "sudo mdutil -a -i off",
      
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
  
  # Final verification (running as new user)
  provisioner "shell" {
    override = {
      tart-cli = {
        ssh_username = var.ssh_username
        ssh_password = var.ssh_password
      }
    }
    
    inline = [
      "echo 'VM setup complete!'",
      "echo 'New admin user: ${var.ssh_username}'",
      "echo 'Default admin user removed'",
      "echo 'SSH and VNC are enabled for the new user'",
      "echo ''",
      "echo 'Users on system:'",
      "dscl . -list /Users | grep -v '^_'"
    ]
  }
}