# Main entry point for macOS 15.5 build
# This file coordinates the build process by including other component files

# Include required plugins
packer {
  required_plugins {
    tart = {
      version = ">= 1.12.0"
      source  = "github.com/cirruslabs/tart"
    }
  }
}

# Path to provisioners directory
variable "provisioners_path" {
  type        = string
  default     = "provisioners"
  description = "Path to provisioning scripts directory"
}

# macOS 15.5 VM configuration variables
variable "vm_name" {
  type        = string
  default     = "macos155"
  description = "Name of the VM image"
}

variable "cpu_count" {
  type        = number
  default     = 4
  description = "Number of CPU cores"
}

variable "memory_gb" {
  type        = number
  default     = 8
  description = "Memory in GB"
}

variable "ipsw_path" {
  type        = string
  default     = ""
  description = "Optional path to a local IPSW file (overrides automatic detection)"
}

variable "disk_size_gb" {
  type        = number
  default     = 50
  description = "Disk size in GB"
}

variable "ssh_username" {
  type        = string
  description = "SSH username (from 1Password)"
  sensitive   = true
}

variable "ssh_password" {
  type        = string
  description = "SSH password (from 1Password)"
  sensitive   = true
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key content (from 1Password)"
  sensitive   = true
}

# Set up local variables for the IPSW file
locals {
  # Define the IPSW filename
  ipsw_filename = "UniversalMac_15.5_24F74_Restore.ipsw"

  # Remote URL as a fallback
  remote_ipsw_url = "https://updates.cdn-apple.com/2025SpringFCS/fullrestores/082-44534/CE6C1054-99A3-4F67-A823-3EE9E6510CDE/UniversalMac_15.5_24F74_Restore.ipsw"

  # Use path.cwd to get the current working directory and go up one level
  # This works when packer is run from the templates directory
  local_ipsw_path = "${path.cwd}/ipsw/${local.ipsw_filename}"

  # Use local file if it exists, otherwise use the URL
  source_ipsw = var.ipsw_path != "" ? var.ipsw_path : (fileexists(local.local_ipsw_path) ? local.local_ipsw_path : local.remote_ipsw_url)
}

# macOS VM configuration
source "tart-cli" "macos" {
  from_ipsw    = local.source_ipsw
  vm_name      = var.vm_name
  cpu_count    = var.cpu_count
  memory_gb    = var.memory_gb
  disk_size_gb = var.disk_size_gb
  ssh_password = var.ssh_password
  ssh_username = var.ssh_username
  ssh_timeout  = "1200s"  # 20 minutes for IPSW builds
  headless     = true
  
  # Boot timing configuration for better reliability
  boot_wait         = "180s"  # Wait 3 minutes for initial boot
  boot_key_interval = "50ms"  # Slower typing speed for reliability
  
  # CRITICAL: Give macOS time to complete SSH setup after boot commands
  # This solves the race condition where Packer tries SSH before daemon is ready
  pause_before_connecting = "60s"

  # ==============================================================================
  # ⚠️ WARNING: BOOT COMMANDS MUST BE CUSTOMIZED FOR EACH MACOS VERSION ⚠️
  # The boot_command sequence below is just an example and WILL NOT WORK as-is
  # for your macOS version. You MUST modify it based on the specific setup flow
  # for your target macOS version. See docs/DEVELOPMENT.md for guidance.
  # ==============================================================================
  boot_command = [
    # hello, hola, bonjour, etc.
    "<wait60s><spacebar>",
    # Language: most of the times we have a list of "English"[1], "English (UK)", etc. with
    # "English" language already selected. If we type "english", it'll cause us to switch
    # to the "English (UK)", which is not what we want. To solve this, we switch to some other
    # language first, e.g. "Italiano" and then switch back to "English". We'll then jump to the
    # first entry in a list of "english"-prefixed items, which will be "English".
    #
    # [1]: should be named "English (US)", but oh well 🤷
    "<wait30s>italiano<esc>english<enter>",
    # Select Your Country or Region
    "<wait30s>united states<leftShiftOn><tab><leftShiftOff><spacebar>",
    # Transfer Your Data to This Mac
    "<wait10s><tab><tab><tab><spacebar><tab><tab><spacebar>",
    # Written and Spoken Languages
    "<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>",
    # Accessibility
    "<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>",
    # Data & Privacy
    "<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>",
    # Create a Mac Account - use credentials from 1Password
    "<wait10s>${var.ssh_username}<tab>${var.ssh_username}<tab>${var.ssh_password}<tab>${var.ssh_password}<tab><tab><spacebar><tab><tab><spacebar>",
    # Enable Voice Over
    "<wait120s><leftAltOn><f5><leftAltOff>",
    # Sign In with Your Apple ID
    "<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>",
    # Are you sure you want to skip signing in with an Apple ID?
    "<wait10s><tab><spacebar>",
    # Terms and Conditions
    "<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>",
    # I have read and agree to the macOS Software License Agreement
    "<wait10s><tab><spacebar>",
    # Enable Location Services
    "<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>",
    # Are you sure you don't want to use Location Services?
    "<wait10s><tab><spacebar>",
    # Select Your Time Zone
    "<wait10s><tab><tab>UTC<enter><leftShiftOn><tab><tab><leftShiftOff><spacebar>",
    # Analytics
    "<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>",
    # Screen Time
    "<wait10s><tab><spacebar>",
    # Siri
    "<wait10s><tab><spacebar><leftShiftOn><tab><leftShiftOff><spacebar>",
    # Choose Your Look
    "<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>",
    # Update Mac Automatically
    "<wait10s><tab><spacebar>",
    # Welcome to Mac
    "<wait10s><spacebar>",
    # Disable Voice Over
    "<leftAltOn><f5><leftAltOff>",
    # Enable Keyboard navigation
    # This is so that we can navigate the System Settings app using the keyboard
    "<wait10s><leftAltOn><spacebar><leftAltOff>Terminal<enter>",
    "<wait10s>defaults write NSGlobalDomain AppleKeyboardUIMode -int 3<enter>",
    "<wait10s><leftAltOn>q<leftAltOff>",
    # Now that the installation is done, open "System Settings"
    "<wait10s><leftAltOn><spacebar><leftAltOff>System Settings<enter>",
    # Navigate to "Sharing"
    "<wait10s><leftCtrlOn><f2><leftCtrlOff><right><right><right><down>Sharing<enter>",
    # Navigate to "Screen Sharing" and enable it
    "<wait10s><tab><tab><tab><tab><tab><tab><tab><spacebar>",
    # Quit System Settings (skip Remote Login through GUI as it's unreliable)
    "<wait10s><leftAltOn>q<leftAltOff>",
    # Disable Gatekeeper (1/2)
    "<wait10s><leftAltOn><spacebar><leftAltOff>Terminal<enter>",
    "<wait10s>sudo spctl --global-disable<enter>",
    "<wait10s>${var.ssh_password}<enter>",
    "<wait10s><leftAltOn>q<leftAltOff>",
    # Disable Gatekeeper (2/2)
    "<wait10s><leftAltOn><spacebar><leftAltOff>System Settings<enter>",
    "<wait10s><leftCtrlOn><f2><leftCtrlOff><right><right><right><down>Privacy & Security<enter>",
    "<wait10s><leftShiftOn><tab><leftShiftOff><leftShiftOn><tab><leftShiftOff><leftShiftOn><tab><leftShiftOff><leftShiftOn><tab><leftShiftOff><leftShiftOn><tab><leftShiftOff><leftShiftOn><tab><leftShiftOff><leftShiftOn><tab><leftShiftOff>",
    "<wait10s><down><wait1s><down><wait1s><enter>",
    "<wait10s>${var.ssh_password}<enter>",
    "<wait10s><leftShiftOn><tab><leftShiftOff><wait1s><spacebar>",
    # Quit System Settings
    "<wait10s><leftAltOn>q<leftAltOff>",
    # Enable SSH, passwordless sudo, and finish setup through Terminal
    "<wait10s><leftAltOn><spacebar><leftAltOff>Terminal<enter>",
    # First: Enable SSH (Remote Login)
    "<wait10s>sudo systemsetup -setremotelogin on<enter>",
    "<wait10s>${var.ssh_password}<enter>",
    # Second: Set up passwordless sudo for reliable SSH provisioning
    "<wait10s>echo '${var.ssh_username} ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/${var.ssh_username}<enter>",
    "<wait10s>${var.ssh_password}<enter>",
    # Close Terminal
    "<wait10s><leftAltOn>q<leftAltOff>",
  ]

  // A (hopefully) temporary workaround for Virtualization.Framework's
  // installation process not fully finishing in a timely manner
  create_grace_time = "30s"

  // Keep the recovery partition, otherwise it's not possible to "softwareupdate"
  recovery_partition = "keep"
}

# Build configuration
build {
  sources = ["source.tart-cli.macos"]

  # Step 1: Configure SSH key (passwordless sudo already set up in boot commands)
  provisioner "shell" {
    inline = [
      "echo 'Setting up SSH key...'",
      "mkdir -p ~/.ssh",
      "chmod 700 ~/.ssh",
      # Ensure proper newline at end and clean any existing keys
      "echo '${var.ssh_public_key}' > ~/.ssh/authorized_keys",
      "echo '' >> ~/.ssh/authorized_keys",  # Ensure trailing newline
      "chmod 600 ~/.ssh/authorized_keys",
      # Verify key was written correctly
      "echo 'Key written. Line count:'",
      "wc -l ~/.ssh/authorized_keys",
      "echo 'SSH key from 1Password configured successfully'"
    ]
  }

  # Step 2: Enable SSH service and verify (now passwordless sudo works)
  provisioner "shell" {
    inline = [
      "echo 'Enabling SSH service...'",
      "sudo systemsetup -setremotelogin on",
      "sudo systemsetup -getremotelogin",
      # Verify SSH daemon is actually running
      "echo 'Checking SSH daemon status:'",
      "sudo launchctl list | grep ssh || echo 'SSH daemon not found in launchctl'",
      # Check SSH configuration
      "echo 'SSH configuration for key authentication:'",
      "sudo cat /etc/ssh/sshd_config | grep -E '(PubkeyAuthentication|AuthorizedKeysFile)' || echo 'No key auth config found'",
      # Restart SSH daemon to pick up new keys
      "sudo launchctl stop com.openssh.sshd",
      "sudo launchctl start com.openssh.sshd"
    ]
  }

  # Step 3: System configuration
  provisioner "shell" {
    inline = [
      "echo 'Configuring system settings...'",
      # Disable screen saver
      "defaults -currentHost write com.apple.screensaver idleTime 0",
      # Disable sleep
      "sudo pmset -a sleep 0",
      "sudo pmset -a disksleep 0", 
      "sudo pmset -a displaysleep 0",
      "echo 'System configuration complete'"
    ]
  }
}
