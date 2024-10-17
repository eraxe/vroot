#!/bin/bash

# -----------------------------------------------------------------------------
# Script Name: vroot_installer.sh
# Description: Installer script for vroot.sh. Installs vroot.sh as the 'vroot' command.
# Author: Arash Abolhasani
# Date: 2024-10-17
# Version: 1.0.0
# -----------------------------------------------------------------------------

set -euo pipefail

# Variables
VROOT_SCRIPT_URL="https://raw.githubusercontent.com/yourusername/vroot_repo/main/vroot.sh"  # Replace with actual URL
INSTALL_PATH="/usr/local/bin/vroot"
CONFIG_DIR="$HOME/.config/vroot"
CONFIG_FILE="$CONFIG_DIR/vroot_config"

# Function to check dependencies
check_dependencies() {
    local dependencies=(curl sudo)
    local missing=()

    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ "${#missing[@]}" -ne 0 ]; then
        echo "The following dependencies are missing: ${missing[*]}"
        echo "Please install them before running the installer."
        exit 1
    fi
}

# Function to download vroot.sh
download_vroot() {
    echo "Downloading vroot.sh..."
    curl -fsSL "$VROOT_SCRIPT_URL" -o "/tmp/vroot.sh"
    echo "Download completed."
}

# Function to install vroot.sh
install_vroot() {
    echo "Installing vroot.sh to $INSTALL_PATH..."
    sudo cp "/tmp/vroot.sh" "$INSTALL_PATH"
    sudo chmod +x "$INSTALL_PATH"
    echo "vroot.sh installed successfully."

    # Create configuration directory if it doesn't exist
    if [ ! -d "$CONFIG_DIR" ]; then
        mkdir -p "$CONFIG_DIR"
        echo "Created configuration directory at $CONFIG_DIR."
    fi

    # Copy default config if not exists
    if [ ! -f "$CONFIG_FILE" ]; then
        sudo cp "/tmp/vroot.sh" "$CONFIG_FILE"
        echo "Default configuration file created at $CONFIG_FILE."
    fi

    # Create symbolic link if necessary
    if [ ! -L "/usr/bin/vroot" ]; then
        sudo ln -s "$INSTALL_PATH" /usr/bin/vroot
        echo "Symbolic link created: /usr/bin/vroot -> $INSTALL_PATH"
    fi
}

# Function to clean up
cleanup() {
    echo "Cleaning up temporary files..."
    rm -f "/tmp/vroot.sh"
    echo "Cleanup completed."
}

# Function to display success message
success_message() {
    echo -e "\e[32m[vroot_installer]\e[0m Installation completed successfully!"
    echo "You can now use the 'vroot' command to manage your containers."
}

# ------------------------------- Main Script ----------------------------------

check_dependencies
download_vroot
install_vroot
cleanup
success_message

exit 0
