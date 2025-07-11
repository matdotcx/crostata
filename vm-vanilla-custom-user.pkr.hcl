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
  default     = null  # Will be loaded from config
}

variable "cpu_count" {
  type        = number
  description = "Number of CPU cores"
  default     = null  # Will be loaded from config
}

variable "memory_gb" {
  type        = number
  description = "Memory in GB"
  default     = null  # Will be loaded from config
}

variable "disk_size_gb" {
  type        = number
  description = "Disk size in GB"
  default     = null  # Will be loaded from config
}

variable "ssh_timeout" {
  type        = string
  description = "SSH connection timeout"
  default     = null  # Will be loaded from config
}

variable "system_settle_delay" {
  type        = number
  description = "Delay for system to settle"
  default     = null  # Will be loaded from config
}

variable "initial_wait" {
  type        = number
  description = "Initial wait time"
  default     = null  # Will be loaded from config
}

variable "connection_retry_delay" {
  type        = number
  description = "Connection retry delay"
  default     = null  # Will be loaded from config
}

# Enhanced Packer configuration with standardized plugin versions
packer {
  required_plugins {
    tart = {
      version = var.tart_version != null ? var.tart_version : ">= 0.5.3"
      source  = var.tart_source != null ? var.tart_source : "github.com/cirruslabs/tart"
    }
  }
}

variable "tart_version" {
  type        = string
  description = "Tart plugin version constraint"
  default     = null  # Will be loaded from config
}

variable "tart_source" {
  type        = string
  description = "Tart plugin source"
  default     = null  # Will be loaded from config
}

# Enhanced source configuration with robust connection handling
source "tart-cli" "custom_vm" {
  vm_base_name = var.base_image != null ? var.base_image : "ghcr.io/cirruslabs/macos-sequoia-vanilla:latest"
  vm_name      = var.vm_name
  cpu_count    = var.cpu_count != null ? var.cpu_count : 4
  memory_gb    = var.memory_gb != null ? var.memory_gb : 8
  disk_size_gb = var.disk_size_gb != null ? var.disk_size_gb : 50
  
  # Enhanced SSH configuration with retry logic
  ssh_username = var.default_username != null ? var.default_username : "admin"
  ssh_password = var.default_password != null ? var.default_password : "admin"
  ssh_timeout  = var.ssh_timeout != null ? var.ssh_timeout : "120s"
  ssh_handshake_attempts = 5
  ssh_keep_alive_interval = "5s"
  
  # Headless mode - no GUI window
  headless = var.headless_mode != null ? var.headless_mode : true
}

variable "default_username" {
  type        = string
  description = "Default username in vanilla image"
  default     = null  # Will be loaded from config
}

variable "default_password" {
  type        = string
  description = "Default password in vanilla image"
  default     = null  # Will be loaded from config
}

variable "headless_mode" {
  type        = bool
  description = "Run VM in headless mode"
  default     = null  # Will be loaded from config
}

# Build configuration
build {
  sources = ["source.tart-cli.custom_vm"]
  
  # Enhanced system settling with validation
  provisioner "shell" {
    max_retries = 2
    timeout     = "30s"
    
    inline = [
      "echo 'Waiting for system to settle...'",
      "sleep ${var.system_settle_delay != null ? var.system_settle_delay : 10}",
      "echo 'System settle delay complete'",
      "uptime",
      "echo 'System ready for user creation'"
    ]
  }
  
  # Enhanced new admin user creation with validation
  provisioner "shell" {
    max_retries = 2
    timeout     = "120s"
    
    inline = [
      "echo 'Creating new admin user: ${var.ssh_username}'",
      
      # Validate user doesn't already exist
      "if dscl . -read /Users/${var.ssh_username} 2>/dev/null; then",
      "  echo 'User ${var.ssh_username} already exists, skipping creation'",
      "  exit 0",
      "fi",
      
      # Find next available UID (starting from 501)
      "NEXT_UID=$(dscl . -list /Users UniqueID | awk '{print $2}' | sort -n | tail -1)",
      "NEXT_UID=$((NEXT_UID + 1))",
      "echo \"Using UID: $NEXT_UID\"",
      
      # Create the new user account with validation
      "sudo dscl . -create /Users/${var.ssh_username} || (echo 'User creation failed' && exit 1)",
      "sudo dscl . -create /Users/${var.ssh_username} UserShell /bin/zsh",
      "sudo dscl . -create /Users/${var.ssh_username} RealName '${var.ssh_username}'",
      "sudo dscl . -create /Users/${var.ssh_username} UniqueID $NEXT_UID",
      "sudo dscl . -create /Users/${var.ssh_username} PrimaryGroupID 20",
      "sudo dscl . -create /Users/${var.ssh_username} NFSHomeDirectory /Users/${var.ssh_username}",
      
      # Set password with validation
      "sudo dscl . -passwd /Users/${var.ssh_username} '${var.ssh_password}' || (echo 'Password setting failed' && exit 1)",
      
      # Create home directory with proper permissions
      "sudo mkdir -p /Users/${var.ssh_username}",
      "sudo chown -R ${var.ssh_username}:staff /Users/${var.ssh_username}",
      "sudo chmod 755 /Users/${var.ssh_username}",
      
      # Add to admin group with validation
      "sudo dscl . -append /Groups/admin GroupMembership ${var.ssh_username}",
      "dscl . -read /Groups/admin GroupMembership | grep -q ${var.ssh_username} || (echo 'Admin group assignment failed' && exit 1)",
      
      # Enhanced passwordless sudo configuration
      "sudo mkdir -p /etc/sudoers.d",
      "echo '${var.ssh_username} ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/${var.ssh_username}",
      "sudo chmod 440 /etc/sudoers.d/${var.ssh_username}",
      "sudo visudo -c || (echo 'Sudoers validation failed' && exit 1)",
      
      # Verify user was created successfully
      "dscl . -read /Users/${var.ssh_username} || (echo 'User verification failed' && exit 1)",
      
      "echo 'New admin user created and validated successfully'"
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
    
    pause_before = "${var.connection_retry_delay != null ? var.connection_retry_delay : 5}s"  # Give system time to settle
    
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