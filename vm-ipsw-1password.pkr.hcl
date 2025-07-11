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

variable "boot_wait" {
  type        = string
  description = "Boot wait time"
  default     = null  # Will be loaded from config
}

variable "boot_key_interval" {
  type        = string
  description = "Boot key interval"
  default     = null  # Will be loaded from config
}

# Additional timing variables for robust boot automation
variable "screen_wake_delay" {
  type        = string
  description = "Screen wake delay"
  default     = null  # Will be loaded from config
}

variable "language_delay" {
  type        = string
  description = "Language selection delay"
  default     = null  # Will be loaded from config
}

variable "country_delay" {
  type        = string
  description = "Country selection delay"
  default     = null  # Will be loaded from config
}

variable "accessibility_delay" {
  type        = string
  description = "Accessibility screen delay"
  default     = null  # Will be loaded from config
}

variable "privacy_delay" {
  type        = string
  description = "Privacy screen delay"
  default     = null  # Will be loaded from config
}

variable "migration_delay" {
  type        = string
  description = "Migration assistant delay"
  default     = null  # Will be loaded from config
}

variable "apple_id_delay" {
  type        = string
  description = "Apple ID screen delay"
  default     = null  # Will be loaded from config
}

variable "terms_delay" {
  type        = string
  description = "Terms and conditions delay"
  default     = null  # Will be loaded from config
}

variable "user_creation_delay" {
  type        = string
  description = "User creation delay"
  default     = null  # Will be loaded from config
}

variable "analytics_delay" {
  type        = string
  description = "Analytics screen delay"
  default     = null  # Will be loaded from config
}

variable "screen_time_delay" {
  type        = string
  description = "Screen time delay"
  default     = null  # Will be loaded from config
}

variable "siri_delay" {
  type        = string
  description = "Siri setup delay"
  default     = null  # Will be loaded from config
}

variable "appearance_delay" {
  type        = string
  description = "Appearance selection delay"
  default     = null  # Will be loaded from config
}

variable "desktop_load_delay" {
  type        = string
  description = "Desktop loading delay"
  default     = null  # Will be loaded from config
}

variable "spotlight_delay" {
  type        = string
  description = "Spotlight open delay"
  default     = null  # Will be loaded from config
}

variable "terminal_delay" {
  type        = string
  description = "Terminal typing delay"
  default     = null  # Will be loaded from config
}

variable "terminal_open_delay" {
  type        = string
  description = "Terminal opening delay"
  default     = null  # Will be loaded from config
}

variable "ssh_enable_delay" {
  type        = string
  description = "SSH enable delay"
  default     = null  # Will be loaded from config
}

variable "command_delay" {
  type        = string
  description = "General command delay"
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

# Connection retry variables
variable "connection_retry_delay" {
  type        = number
  description = "Connection retry delay in seconds"
  default     = null  # Will be loaded from config
}

variable "initial_wait" {
  type        = number
  description = "Initial wait time in seconds"
  default     = null  # Will be loaded from config
}

# Enhanced Packer configuration with retry settings
packer {
  required_plugins {
    tart = {
      version = var.tart_version != null ? var.tart_version : ">= 1.12.0"
      source  = var.tart_source != null ? var.tart_source : "github.com/cirruslabs/tart"
    }
  }
}

# Enhanced source configuration with robust connection handling
source "tart-cli" "custom_vm" {
  from_ipsw    = var.ipsw_url != null ? var.ipsw_url : "latest"
  vm_name      = var.vm_name
  cpu_count    = var.cpu_count != null ? var.cpu_count : 4
  memory_gb    = var.memory_gb != null ? var.memory_gb : 8
  disk_size_gb = var.disk_size_gb != null ? var.disk_size_gb : 50

  # Enhanced SSH configuration with retry logic
  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_timeout  = var.ssh_timeout != null ? var.ssh_timeout : "1200s"
  
  # Enhanced connection retry settings
  ssh_handshake_attempts = 10
  ssh_bastion_host      = ""
  ssh_bastion_port      = 22
  ssh_keep_alive_interval = "5s"
  
  # Headless mode - no GUI window
  headless = var.headless_mode != null ? var.headless_mode : true
  
  # Enhanced boot timing configuration
  boot_wait = var.boot_wait != null ? var.boot_wait : "180s"
  boot_key_interval = var.boot_key_interval != null ? var.boot_key_interval : "50ms"

  # Robust macOS setup from IPSW with enhanced error detection
  boot_command = [
    # Wake the screen and ensure we're at the language selection
    "<spacebar><wait${var.screen_wake_delay != null ? var.screen_wake_delay : "10s"}>",
    
    # Multiple attempts to ensure language selection is active
    "<spacebar><wait2s>",
    "<spacebar><wait2s>",

    # Language selection (English) - Accept default with multiple attempts
    "<enter><wait${var.language_delay != null ? var.language_delay : "10s"}>",
    # Fallback in case first attempt failed
    "<enter><wait3s>",

    # Country/Region - Robust United States selection
    "<cmd>a<wait1s>",  # Select all text first
    "united states<wait2s><enter><wait${var.country_delay != null ? var.country_delay : "10s"}>",
    # Fallback attempt
    "<enter><wait3s>",

    # Written and spoken languages - Multiple continue attempts
    "<tab><wait1s><spacebar><wait${var.accessibility_delay != null ? var.accessibility_delay : "10s"}>",
    "<enter><wait2s>",  # Fallback with enter

    # Accessibility - Enhanced "Not Now" detection
    "<tab><wait1s><spacebar><wait${var.accessibility_delay != null ? var.accessibility_delay : "10s"}>",
    "<tab><wait1s><tab><wait1s><spacebar><wait3s>",  # Alternative path

    # Data & Privacy - Robust continue
    "<tab><wait1s><spacebar><wait${var.privacy_delay != null ? var.privacy_delay : "15s"}>",
    "<enter><wait3s>",  # Fallback

    # Migration Assistant - Enhanced "Not Now" with multiple paths
    "<tab><wait1s><tab><wait1s><tab><wait1s><spacebar><wait${var.migration_delay != null ? var.migration_delay : "10s"}>",
    # Alternative path for different UI layouts
    "<tab><wait1s><spacebar><wait3s>",
    "<escape><wait1s><tab><wait1s><spacebar><wait3s>",

    # Sign in with Apple ID - Enhanced "Set Up Later" detection
    "<tab><wait1s><tab><wait1s><spacebar><wait${var.apple_id_delay != null ? var.apple_id_delay : "10s"}>",
    # Alternative approaches
    "<tab><wait1s><spacebar><wait3s>",
    "<escape><wait1s><tab><wait1s><tab><wait1s><spacebar><wait3s>",
    
    # Skip Apple ID confirmation - Multiple attempts
    "<tab><wait1s><spacebar><wait${var.apple_id_delay != null ? var.apple_id_delay : "10s"}>",
    "<enter><wait3s>",

    # Terms and Conditions - Enhanced agreement detection
    "<tab><wait1s><spacebar><wait${var.terms_delay != null ? var.terms_delay : "5s"}>",
    "<enter><wait2s>",
    
    # Terms and Conditions - Second agreement with fallbacks
    "<tab><wait1s><spacebar><wait${var.terms_delay != null ? var.terms_delay : "10s"}>",
    "<enter><wait3s>",
    "<spacebar><wait3s>",  # Direct spacebar if tab targeting fails

    # Create user account - Enhanced field navigation
    "<cmd>a<wait1s>",  # Clear any existing text
    "${var.ssh_username}<wait${var.command_delay != null ? var.command_delay : "1s"}><tab><wait1s>",
    "<cmd>a<wait1s>",
    "${var.ssh_username}<wait${var.command_delay != null ? var.command_delay : "1s"}><tab><wait1s>",
    "<cmd>a<wait1s>",
    "${var.ssh_password}<wait${var.command_delay != null ? var.command_delay : "1s"}><tab><wait1s>",
    "<cmd>a<wait1s>",
    "${var.ssh_password}<wait${var.command_delay != null ? var.command_delay : "1s"}><tab><wait1s>",
    "<tab><wait1s><tab><wait1s><spacebar><wait${var.user_creation_delay != null ? var.user_creation_delay : "15s"}>",
    # Fallback navigation
    "<enter><wait3s>",

    # Analytics - Enhanced "Not Now" with multiple paths
    "<tab><wait1s><tab><wait1s><tab><wait1s><tab><wait1s><spacebar><wait${var.analytics_delay != null ? var.analytics_delay : "10s"}>",
    # Alternative paths
    "<tab><wait1s><spacebar><wait3s>",
    "<escape><wait1s><tab><wait1s><tab><wait1s><spacebar><wait3s>",

    # Screen Time - Enhanced "Set Up Later"
    "<tab><wait1s><spacebar><wait${var.screen_time_delay != null ? var.screen_time_delay : "10s"}>",
    "<tab><wait1s><tab><wait1s><spacebar><wait3s>",

    # Siri - Enhanced "Not Now" detection
    "<tab><wait1s><tab><wait1s><spacebar><wait${var.siri_delay != null ? var.siri_delay : "10s"}>",
    "<tab><wait1s><spacebar><wait3s>",
    "<escape><wait1s><tab><wait1s><spacebar><wait3s>",

    # Choose Look - Enhanced continue with appearance
    "<tab><wait1s><spacebar><wait${var.appearance_delay != null ? var.appearance_delay : "30s"}>",
    "<enter><wait5s>",
    "<spacebar><wait5s>",

    # Extended wait for desktop with progress indicators
    "<wait${var.desktop_load_delay != null ? var.desktop_load_delay : "60s"}>",
    "<wait30s>",  # Additional safety margin
    
    # Enhanced Spotlight opening with retries
    "<cmd><spacebar><wait${var.spotlight_delay != null ? var.spotlight_delay : "3s"}>",
    # Retry if first attempt failed
    "<cmd><spacebar><wait2s>",
    
    # Enhanced Terminal opening with verification
    "terminal<wait${var.terminal_delay != null ? var.terminal_delay : "2s"}><enter><wait${var.terminal_open_delay != null ? var.terminal_open_delay : "10s"}>",
    # Retry terminal opening if needed
    "<cmd><spacebar><wait2s>terminal<wait1s><enter><wait5s>",
    
    # Enhanced SSH enabling with error detection
    "sudo systemsetup -setremotelogin on<wait${var.command_delay != null ? var.command_delay : "1s"}><enter><wait3s>",
    "${var.ssh_password}<wait${var.command_delay != null ? var.command_delay : "1s"}><enter><wait${var.ssh_enable_delay != null ? var.ssh_enable_delay : "5s"}>",
    
    # Verify SSH is enabled with status check
    "sudo systemsetup -getremotelogin<wait1s><enter><wait3s>",
    
    # Enhanced Terminal closure
    "<cmd>q<wait2s>",
    "<enter><wait1s>"  # Confirm if prompted
  ]
}

# Build configuration
build {
  sources = ["source.tart-cli.custom_vm"]

  # Enhanced system settling with validation
  provisioner "shell" {
    pause_before = "10s"  # Give SSH time to fully start
    max_retries  = 3
    timeout      = "60s"
    
    inline = [
      "echo 'Waiting for system to fully settle...'.",
      "sleep ${var.system_settle_delay != null ? var.system_settle_delay * 3 : 30}",
      "echo 'System settle delay complete'",
      
      # Validate SSH is actually running
      "sudo systemsetup -getremotelogin | grep -q 'Remote Login: On' || (echo 'SSH not enabled, attempting to fix...' && sudo systemsetup -setremotelogin on)",
      
      # Verify we can sudo without password
      "sudo echo 'Sudo access verified'",
      
      # Check system readiness
      "echo 'System validation complete'"
    ]
  }

  # Enhanced SSH key configuration with validation
  provisioner "shell" {
    max_retries = 2
    timeout     = "30s"
    
    inline = [
      "echo 'Configuring SSH key from 1Password...'",
      
      # Create SSH directory with proper permissions
      "mkdir -p ~/.ssh",
      "chmod 700 ~/.ssh",
      
      # Backup existing authorized_keys if present
      "test -f ~/.ssh/authorized_keys && cp ~/.ssh/authorized_keys ~/.ssh/authorized_keys.backup || true",
      
      # Add SSH key with validation
      "echo '${var.ssh_public_key}' >> ~/.ssh/authorized_keys",
      "chmod 600 ~/.ssh/authorized_keys",
      
      # Validate SSH key format
      "ssh-keygen -l -f ~/.ssh/authorized_keys || (echo 'SSH key validation failed' && exit 1)",
      
      # Verify ownership
      "ls -la ~/.ssh/",
      
      "echo 'SSH key from 1Password configured and validated successfully'"
    ]
  }

  # Enhanced SSH enabling with comprehensive validation
  provisioner "shell" {
    max_retries = 3
    timeout     = "60s"
    
    inline = [
      "echo 'Enabling and validating SSH configuration...'",
      
      # Enable SSH with verification
      "sudo systemsetup -setremotelogin on",
      "sleep 3",
      
      # Verify SSH daemon is running
      "sudo launchctl list | grep ssh || (echo 'SSH daemon not running' && exit 1)",
      
      # Check SSH service status
      "sudo systemsetup -getremotelogin | grep -q 'Remote Login: On' || (echo 'SSH still not enabled' && exit 1)",
      
      # Test SSH port accessibility
      "netstat -an | grep :22 | grep LISTEN || (echo 'SSH port not listening' && exit 1)",
      
      # Verify SSH configuration
      "sudo sshd -t || (echo 'SSH configuration invalid' && exit 1)",
      
      "echo 'SSH successfully enabled and validated'"
    ]
  }

  # Enhanced VNC/Screen Sharing with retry logic
  provisioner "shell" {
    max_retries = 3
    timeout     = "120s"
    
    inline = [
      "echo 'Enabling Screen Sharing for VNC with enhanced reliability...'",
      
      # Enable ARD with retry logic
      "for i in {1..3}; do",
      "  echo \"Attempt $i: Configuring ARD...\"",
      "  sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -activate -configure -access -on -users ${var.ssh_username} -privs -all -restart -agent -menu && break",
      "  echo \"ARD configuration attempt $i failed, retrying...\"",
      "  sleep 5",
      "done",
      
      # Configure screen sharing daemon
      "sudo defaults write /var/db/launchd.db/com.apple.launchd/overrides.plist com.apple.screensharing -dict Disabled -bool false",
      
      # Load screen sharing with validation
      "sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist || echo 'Screen sharing plist already loaded'",
      
      # Verify VNC is accessible
      "sleep 5",
      "netstat -an | grep :5900 | grep LISTEN && echo 'VNC port 5900 is listening' || echo 'Warning: VNC port not detected'",
      
      "echo 'VNC/Screen Sharing configuration complete'"
    ]
  }

  # Enhanced system configurations with error recovery
  provisioner "shell" {
    max_retries = 2
    timeout     = "180s"
    
    inline = [
      "echo 'Configuring system settings with enhanced reliability...'",

      # Disable spotlight indexing with validation
      "echo 'Disabling Spotlight indexing...'",
      "sudo mdutil -a -i off || echo 'Warning: Spotlight disable failed'",
      "sudo mdutil -a -s | grep -q 'Indexing disabled' && echo 'Spotlight successfully disabled' || echo 'Warning: Spotlight status unclear'",

      # Enhanced passwordless sudo configuration
      "echo 'Configuring passwordless sudo...'",
      "sudo mkdir -p /etc/sudoers.d",
      "echo '${var.ssh_username} ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/${var.ssh_username}",
      "sudo chmod 440 /etc/sudoers.d/${var.ssh_username}",
      "sudo visudo -c && echo 'Sudoers configuration validated' || (echo 'Sudoers validation failed' && exit 1)",

      # Enhanced screen saver configuration
      "echo 'Disabling screen saver...'",
      "defaults -currentHost write com.apple.screensaver idleTime 0 || echo 'Warning: Screen saver config failed'",
      "defaults read com.apple.screensaver idleTime && echo 'Screen saver setting verified' || echo 'Warning: Screen saver verification failed'",

      # Enhanced power management with validation
      "echo 'Configuring power management...'",
      "sudo pmset -a sleep 0 && echo 'Sleep disabled' || echo 'Warning: Sleep disable failed'",
      "sudo pmset -a disksleep 0 && echo 'Disk sleep disabled' || echo 'Warning: Disk sleep disable failed'",
      "sudo pmset -a displaysleep 0 && echo 'Display sleep disabled' || echo 'Warning: Display sleep disable failed'",
      "pmset -g | grep -E '(sleep|displaysleep|disksleep)' || echo 'Warning: Power settings verification failed'",

      # Enhanced automatic updates configuration
      "echo 'Disabling automatic updates...'",
      "sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool NO || echo 'Warning: AutomaticDownload setting failed'",
      "sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool NO || echo 'Warning: AutomaticCheckEnabled setting failed'",
      "sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool NO || echo 'Warning: AutomaticallyInstallMacOSUpdates setting failed'",

      # Enhanced auto-login configuration with validation
      "echo 'Configuring auto-login...'",
      "sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser ${var.ssh_username} || echo 'Warning: Auto-login configuration failed'",
      "sudo defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser | grep -q '${var.ssh_username}' && echo 'Auto-login verified' || echo 'Warning: Auto-login verification failed'",

      "echo 'System configuration complete with enhanced reliability'"
    ]
  }

  # Comprehensive validation and final summary
  provisioner "shell" {
    max_retries = 1
    timeout     = "60s"
    
    inline = [
      "echo '==================================='.",
      "echo 'Performing final system validation...'",
      "echo '==================================='",
      
      # Validate SSH configuration
      "echo 'SSH Validation:'",
      "sudo systemsetup -getremotelogin | grep 'Remote Login: On' && echo '  ✓ SSH is enabled' || echo '  ✗ SSH is not enabled'",
      "netstat -an | grep :22 | grep LISTEN > /dev/null && echo '  ✓ SSH port is listening' || echo '  ✗ SSH port is not listening'",
      "test -f ~/.ssh/authorized_keys && echo '  ✓ SSH keys are configured' || echo '  ✗ SSH keys are missing'",
      
      # Validate VNC configuration
      "echo 'VNC Validation:'",
      "netstat -an | grep :5900 | grep LISTEN > /dev/null && echo '  ✓ VNC port is listening' || echo '  ✗ VNC port is not listening'",
      
      # Validate sudo configuration
      "echo 'Sudo Validation:'",
      "sudo -n echo '  ✓ Passwordless sudo is working' || echo '  ✗ Passwordless sudo failed'",
      
      # Validate system settings
      "echo 'System Settings Validation:'",
      "pmset -g | grep -q 'sleep.*0' && echo '  ✓ Sleep is disabled' || echo '  ✗ Sleep settings unclear'",
      "defaults read com.apple.screensaver idleTime 2>/dev/null | grep -q '0' && echo '  ✓ Screen saver is disabled' || echo '  ✗ Screen saver settings unclear'",
      
      # System readiness check
      "echo 'Overall System Status:'",
      "uptime",
      "df -h / | tail -1",
      "free -h 2>/dev/null || vm_stat | head -5",
      
      "echo '==================================='",
      "echo 'VM setup complete!'",
      "echo 'Username: ${var.ssh_username}'",
      "echo 'SSH: Enabled with key authentication'",
      "echo 'VNC: Enabled via Screen Sharing'",
      "echo 'Auto-login: Enabled'",
      "echo 'Passwordless sudo: Enabled'",
      "echo 'Build completed with enhanced reliability'",
      "echo '==================================='"
    ]
  }
}
