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

variable "headless_mode" {
  type        = bool
  description = "Run VM in headless mode"
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

# Enhanced source configuration with improved connection reliability
source "tart-cli" "custom_vm" {
  vm_base_name = var.base_image != null ? var.base_image : "ghcr.io/cirruslabs/macos-sequoia-vanilla:latest"
  vm_name      = var.vm_name
  cpu_count    = var.cpu_count != null ? var.cpu_count : 4
  memory_gb    = var.memory_gb != null ? var.memory_gb : 8
  disk_size_gb = var.disk_size_gb != null ? var.disk_size_gb : 50
  
  # Enhanced SSH configuration
  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_timeout  = var.ssh_timeout != null ? var.ssh_timeout : "120s"
  ssh_handshake_attempts = 5
  ssh_keep_alive_interval = "5s"
  
  # Headless mode - no GUI window
  headless = var.headless_mode != null ? var.headless_mode : true
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
      "echo 'System ready for configuration'"
    ]
  }
  
  # Enhanced SSH key configuration with validation
  provisioner "shell" {
    max_retries = 2
    timeout     = "30s"
    
    inline = [
      "echo 'Configuring SSH key from 1Password...'",
      "mkdir -p ~/.ssh",
      "chmod 700 ~/.ssh",
      
      # Backup existing keys if present
      "test -f ~/.ssh/authorized_keys && cp ~/.ssh/authorized_keys ~/.ssh/authorized_keys.backup || true",
      
      # Add SSH key with validation
      "echo '${var.ssh_public_key}' >> ~/.ssh/authorized_keys",
      "chmod 600 ~/.ssh/authorized_keys",
      
      # Validate SSH key format
      "ssh-keygen -l -f ~/.ssh/authorized_keys || (echo 'SSH key validation failed' && exit 1)",
      
      "echo 'SSH key configured and validated successfully'"
    ]
  }
  
  # Enhanced VNC/Screen Sharing with retry logic
  provisioner "shell" {
    max_retries = 3
    timeout     = "60s"
    
    inline = [
      "echo 'Enabling Screen Sharing with enhanced reliability...'",
      
      # Enable ARD with retry logic
      "for i in {1..3}; do",
      "  echo \"Attempt $i: Configuring ARD...\"",
      "  sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -activate -configure -access -on -users ${var.ssh_username} -privs -all -restart -agent -menu && break",
      "  echo \"ARD configuration attempt $i failed, retrying...\"",
      "  sleep 3",
      "done",
      
      # Configure screen sharing
      "sudo defaults write /var/db/launchd.db/com.apple.launchd/overrides.plist com.apple.screensharing -dict Disabled -bool false",
      "sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist || echo 'Screen sharing already loaded'",
      
      # Verify VNC accessibility
      "sleep 3",
      "netstat -an | grep :5900 | grep LISTEN && echo 'VNC port 5900 is listening' || echo 'Warning: VNC port not detected'",
      
      "echo 'Screen Sharing configuration complete'"
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
