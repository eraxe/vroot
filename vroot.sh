#!/bin/bash

# -----------------------------------------------------------------------------
# Script Name: vroot.sh
# Description: Enhanced command-line tool to manage Podman AlmaLinux containers with
#              OpenLiteSpeed. Supports creating, entering, listing, removing containers,
#              managing systemd services, backup & restore, and more.
# Author: Arash Abolhasani 
# Date: 2024-10-17
# Version: 3.4.0
# -----------------------------------------------------------------------------

set -euo pipefail

# ------------------------------- Configuration ------------------------------

# Default configurations
DEFAULT_BASE_IMAGE="almalinux:latest"
DEFAULT_PORT=60000
DEFAULT_ALIAS="vroot"
DEFAULT_DATA_DIR="$(pwd)/containers_data"
DEFAULT_PACKAGE_GROUP="base"
CONFIG_FILE="$HOME/.vroot_config"

# Additional packages to install by default
DEFAULT_PACKAGES=("git" "vim" "curl")

# Resource limits
DEFAULT_CPU="1"
DEFAULT_MEMORY="512m"

# Colors for echo functions (removed for UI enhancement)
COLOR_INFO="[INFO]"
COLOR_SUCCESS="[SUCCESS]"
COLOR_WARNING="[WARNING]"
COLOR_ERROR="[ERROR]"

# ------------------------------- Functions ------------------------------------

# Function to display informational messages
echo_info() {
    echo -e "${COLOR_INFO} $1"
}

# Function to display success messages
echo_success() {
    echo -e "${COLOR_SUCCESS} $1"
}

# Function to display warning messages
echo_warning() {
    echo -e "${COLOR_WARNING} $1"
}

# Function to display error messages
echo_error() {
    echo -e "${COLOR_ERROR} $1" >&2
}

# Function to display help
display_help() {
    cat << HELP
vroot - Manage Podman AlmaLinux containers with OpenLiteSpeed

Usage:
  vroot <command> [options]

Commands:
  create       Create a new container
  enter        Enter an existing container
  list         List all managed containers
  remove       Remove a container
  backup       Backup container data
  restore      Restore container data from backup
  service      Manage systemd service for a container
  ui           Launch the user-friendly UI
  help         Display this help message

Use "vroot <command> --help" for more information on a command.

Examples:
  # Create a new container with default settings
  vroot create

  # Create a new container with custom base image and port
  vroot create --base-image almalinux:9 --port 50000 --alias alma1

  # Enter an existing container named 'alma1'
  vroot enter --image-name alma1

HELP
}

# Function to display create subcommand help
display_create_help() {
    cat << HELP
Usage:
  vroot create [OPTIONS]

Options:
      --base-image       Specify the base image (default: almalinux:latest)
      --port             Specify the host port (default: 60000)
      --dir              Specify the data directory (default: current directory/containers_data)
      --alias            Specify the alias name (default: vroot)
      --packages         Comma-separated list of packages to install (default: git,vim,curl)
      --cpu              CPU limit for the container (default: 1)
      --memory           Memory limit for the container (default: 512m)
      --help             Display this help message

Examples:
  # Create a new container with default settings
  vroot create

  # Create a new container with custom base image and port
  vroot create --base-image almalinux:9 --port 50000 --alias alma1 --packages git,vim,htop --cpu 2 --memory 1g

HELP
}

# Function to display enter subcommand help
display_enter_help() {
    cat << HELP
Usage:
  vroot enter [OPTIONS]

Options:
      --image-name       Specify the container name to enter (required)
      --help             Display this help message

Examples:
  # Enter an existing container named 'alma1'
  vroot enter --image-name alma1

HELP
}

# Function to display list subcommand help
display_list_help() {
    cat << HELP
Usage:
  vroot list [OPTIONS]

Options:
      --all              List all containers including stopped ones
      --running          List only running containers
      --stopped          List only stopped containers
      --help             Display this help message

Examples:
  # List all managed containers
  vroot list

  # List only running containers
  vroot list --running

HELP
}

# Function to display remove subcommand help
display_remove_help() {
    cat << HELP
Usage:
  vroot remove [OPTIONS]

Options:
      --image-name       Specify the container name to remove (required)
      --force            Force removal of running container
      --help             Display this help message

Examples:
  # Remove a container named 'alma1'
  vroot remove --image-name alma1

HELP
}

# Function to display backup subcommand help
display_backup_help() {
    cat << HELP
Usage:
  vroot backup [OPTIONS]

Options:
      --image-name       Specify the container name to backup (required)
      --backup-dir       Specify the backup directory (default: \$HOME/backups)
      --help             Display this help message

Examples:
  # Backup a container named 'alma1'
  vroot backup --image-name alma1

HELP
}

# Function to display restore subcommand help
display_restore_help() {
    cat << HELP
Usage:
  vroot restore [OPTIONS]

Options:
      --image-name       Specify the container name to restore (required)
      --backup-file      Specify the backup file path (required)
      --help             Display this help message

Examples:
  # Restore a container named 'alma1' from backup
  vroot restore --image-name alma1 --backup-file backups/alma1_backup.tar

HELP
}

# Function to display service subcommand help
display_service_help() {
    cat << HELP
Usage:
  vroot service <subcommand> [OPTIONS]

Subcommands:
      start             Start the systemd service for a container
      stop              Stop the systemd service for a container
      restart           Restart the systemd service for a container
      status            Check the status of the systemd service for a container

Options:
      --image-name       Specify the container name (required for all subcommands)
      --help             Display this help message

Examples:
  # Start the service for 'alma1'
  vroot service start --image-name alma1

  # Check the status of the service for 'alma1'
  vroot service status --image-name alma1

HELP
}

# Function to check dependencies
check_dependencies() {
    local dependencies=(podman dialog lsof systemctl wget tar gcc make openssl firewall-cmd)
    local missing=()

    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ "${#missing[@]}" -ne 0 ]; then
        echo_error "The following dependencies are missing: ${missing[*]}"
        echo_info "Please install them before running this script."
        exit 1
    fi
}

# Function to load configuration from config file
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        echo_info "Loaded configuration from $CONFIG_FILE"
    else
        echo_warning "Configuration file $CONFIG_FILE not found. Using default settings."
    fi
}

# Function to determine the user's shell configuration file
determine_shell_config() {
    case "$SHELL" in
        */bash)
            SHELL_CONFIG="$HOME/.bashrc"
            ;;
        */zsh)
            SHELL_CONFIG="$HOME/.zshrc"
            ;;
        */fish)
            SHELL_CONFIG="$HOME/.config/fish/config.fish"
            ;;
        *)
            echo_warning "Unsupported shell. Defaulting to ~/.bashrc"
            SHELL_CONFIG="$HOME/.bashrc"
            ;;
    esac
}

# Function to create a unique container name using alias
generate_unique_name() {
    local alias_name="$1"
    echo "$alias_name"
}

# Function to determine the next available host port starting from DEFAULT_PORT
get_next_available_port() {
    local port="${1:-$DEFAULT_PORT}"
    while ! [[ "$port" -ge 1 && "$port" -le 65535 ]]; do
        echo_warning "Port $port is out of range. Incrementing to find an available port."
        port=$((port + 1))
        if [ "$port" -gt 65535 ]; then
            echo_error "No available ports found."
            exit 1
        fi
    done

    while lsof -i ":$port" &> /dev/null; do
        echo_info "Port $port is in use. Checking next port."
        port=$((port + 1))
        if [ "$port" -gt 65535 ]; then
            echo_error "No available ports found."
            exit 1
        fi
    done
    echo "$port"
}

# Function to check if a Podman image exists
podman_image_exists() {
    local image="$1"
    if podman image exists "$image"; then
        return 0
    else
        return 1
    fi
}

# Function to check if a Podman container exists
podman_container_exists() {
    local container="$1"
    if podman container exists "$container"; then
        return 0
    else
        return 1
    fi
}

# Function to create a Podman container with OpenLiteSpeed and default packages
create_container() {
    local BASE_IMAGE="$1"
    local HOST_PORT="$2"
    local CONTAINER_DIR="$3"
    local ALIAS_NAME="$4"
    local PACKAGES="$5"
    local CPU_LIMIT="$6"
    local MEMORY_LIMIT="$7"

    # Check if alias is already used
    if podman_container_exists "$ALIAS_NAME"; then
        echo_error "A container with alias '$ALIAS_NAME' already exists. Choose a different alias."
        exit 1
    fi

    # Validate HOST_PORT
    if [ -n "$HOST_PORT" ]; then
        if ! [[ "$HOST_PORT" =~ ^[0-9]+$ ]]; then
            echo_warning "Invalid port number: $HOST_PORT. It must be a number between 1 and 65535."
            HOST_PORT=""
        elif [ "$HOST_PORT" -lt 1 ] || [ "$HOST_PORT" -gt 65535 ]; then
            echo_warning "Port number $HOST_PORT is out of valid range (1-65535)."
            HOST_PORT=""
        fi
    fi

    # Generate container name (using alias)
    local CONTAINER_NAME
    CONTAINER_NAME=$(generate_unique_name "$ALIAS_NAME")

    # Create container directory if it doesn't exist
    local DATA_DIR="${CONTAINER_DIR}/${CONTAINER_NAME}_data"
    if [ ! -d "$DATA_DIR" ]; then
        mkdir -p "$DATA_DIR"
        echo_info "Created directory for container data: $DATA_DIR"
    else
        echo_info "Directory for container data already exists: $DATA_DIR"
    fi

    # Pull the base image if not already present
    if ! podman_image_exists "$BASE_IMAGE"; then
        echo_info "Pulling base image: $BASE_IMAGE"
        podman pull "$BASE_IMAGE"
    else
        echo_info "Base image already exists: $BASE_IMAGE"
    fi

    # Determine the next available port if port is not specified
    if [ -z "$HOST_PORT" ]; then
        HOST_PORT=$(get_next_available_port)
        echo_info "Assigned host port: $HOST_PORT"
    fi

    # Run the container with resource limits
    echo_info "Creating and starting container: $CONTAINER_NAME on port $HOST_PORT with CPU: $CPU_LIMIT and Memory: $MEMORY_LIMIT"
    podman run -d \
        --name "$CONTAINER_NAME" \
        -p "${HOST_PORT}:80" \
        -v "$DATA_DIR":/var/www/html \
        --cpus "$CPU_LIMIT" \
        --memory "$MEMORY_LIMIT" \
        "$BASE_IMAGE" \
        /bin/bash -c "while true; do sleep 1000; done"

    echo_success "Container $CONTAINER_NAME created and started on host port $HOST_PORT."

    # Install OpenLiteSpeed and default packages inside the container
    install_packages "$CONTAINER_NAME" "$PACKAGES"
    install_openlitespeed "$CONTAINER_NAME"

    # Configure firewall for the container port
    configure_firewall "$HOST_PORT"

    # Create systemd service if not exists
    if ! systemd_service_exists "$CONTAINER_NAME"; then
        create_systemd_service "$CONTAINER_NAME"
    else
        echo_warning "Systemd service for container $CONTAINER_NAME already exists."
    fi

    echo_success "Container setup complete."
    echo_info "You can access the container using the command: vroot enter --image-name $CONTAINER_NAME"
    echo_info "OpenLiteSpeed is accessible on host port: $HOST_PORT"
}

# Function to check if a systemd service exists
systemd_service_exists() {
    local CONTAINER_NAME="$1"
    local SERVICE_FILE="/etc/systemd/system/pm-${CONTAINER_NAME}.service"
    if [ -f "$SERVICE_FILE" ]; then
        return 0
    else
        return 1
    fi
}

# Function to install OpenLiteSpeed inside the container
install_openlitespeed() {
    local CONTAINER_NAME="$1"

    echo_info "Installing OpenLiteSpeed in container: $CONTAINER_NAME"

    podman exec -u root "$CONTAINER_NAME" bash -c "
        dnf install -y epel-release
        dnf install -y yum-utils
        yum-config-manager --add-repo http://rpms.litespeedtech.com/centos/litespeed.repo
        dnf install -y openlitespeed
        systemctl enable lsws
        systemctl start lsws
    "

    echo_success "OpenLiteSpeed installed and started in container: $CONTAINER_NAME"
}

# Function to install additional packages inside the container
install_packages() {
    local CONTAINER_NAME="$1"
    local PACKAGES="$2"

    if [ -n "$PACKAGES" ]; then
        IFS=',' read -ra PKG_ARRAY <<< "$PACKAGES"
        echo_info "Installing additional packages in container: $CONTAINER_NAME"
        podman exec -u root "$CONTAINER_NAME" bash -c "dnf install -y ${PKG_ARRAY[*]}"
        echo_success "Installed packages: ${PKG_ARRAY[*]} in container: $CONTAINER_NAME"
    else
        echo_warning "No additional packages specified for container: $CONTAINER_NAME"
    fi
}

# Function to create a systemd service for the container
create_systemd_service() {
    local CONTAINER_NAME="$1"
    if [ -z "$CONTAINER_NAME" ]; then
        echo_error "Container name is empty. Cannot create systemd service."
        return 1
    fi

    local SERVICE_NAME="pm-${CONTAINER_NAME}.service"
    local SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"

    echo_info "Creating systemd service for container: $CONTAINER_NAME"

    sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=Podman container $CONTAINER_NAME
After=network.target

[Service]
Restart=always
ExecStart=/usr/bin/podman start -a $CONTAINER_NAME
ExecStop=/usr/bin/podman stop -t 10 $CONTAINER_NAME

[Install]
WantedBy=multi-user.target
EOF

    if [ $? -ne 0 ]; then
        echo_error "Failed to create systemd service file."
        return 1
    fi

    sudo systemctl daemon-reload
    if sudo systemctl enable "$SERVICE_NAME"; then
        echo_success "Systemd service enabled for container: $CONTAINER_NAME"
        if sudo systemctl start "$SERVICE_NAME"; then
            echo_success "Systemd service started for container: $CONTAINER_NAME"
        else
            echo_error "Failed to start systemd service for container: $CONTAINER_NAME"
        fi
    else
        echo_error "Failed to enable systemd service for container: $CONTAINER_NAME"
    fi
}

# Function to manage firewall for container ports
configure_firewall() {
    local PORT="$1"

    echo_info "Configuring firewall to allow traffic on port $PORT"
    sudo firewall-cmd --permanent --add-port=${PORT}/tcp
    sudo firewall-cmd --reload
    echo_success "Firewall configured for port $PORT"
}

# Function to list containers
list_containers() {
    local filter="$1" # "all", "running", "stopped"

    case "$filter" in
        all)
            podman ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
            ;;
        running)
            podman ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
            ;;
        stopped)
            podman ps -a --filter "status=exited" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
            ;;
        *)
            podman ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
            ;;
    esac
}

# Function to remove a container and its systemd service
remove_container() {
    local CONTAINER_NAME="$1"
    local FORCE="$2"

    if ! podman_container_exists "$CONTAINER_NAME"; then
        echo_error "Container $CONTAINER_NAME does not exist."
        exit 1
    fi

    # Stop the container if running
    local STATUS
    STATUS=$(podman inspect -f '{{.State.Status}}' "$CONTAINER_NAME")
    if [ "$STATUS" == "running" ]; then
        if [ "$FORCE" == "true" ]; then
            echo_info "Force stopping running container: $CONTAINER_NAME"
            podman stop "$CONTAINER_NAME"
        else
            echo_error "Container $CONTAINER_NAME is running. Use --force to stop and remove it."
            exit 1
        fi
    fi

    # Remove the container
    echo_info "Removing container: $CONTAINER_NAME"
    podman rm "$CONTAINER_NAME"

    echo_success "Container $CONTAINER_NAME removed."

    # Remove associated systemd service if exists
    local SERVICE_NAME="pm-${CONTAINER_NAME}.service"
    local SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"
    if [ -f "$SERVICE_FILE" ]; then
        echo_info "Removing systemd service for container: $CONTAINER_NAME"
        sudo systemctl stop "$SERVICE_NAME" &> /dev/null || true
        sudo systemctl disable "$SERVICE_NAME" &> /dev/null || true
        sudo rm -f "$SERVICE_FILE"
        sudo systemctl daemon-reload
        echo_success "Systemd service for container $CONTAINER_NAME removed."
    else
        echo_warning "No systemd service found for container: $CONTAINER_NAME"
    fi
}

# Function to backup container data
backup_container() {
    local CONTAINER_NAME="$1"
    local BACKUP_DIR="$2"

    if ! podman_container_exists "$CONTAINER_NAME"; then
        echo_error "Container $CONTAINER_NAME does not exist."
        exit 1
    fi

    local TIMESTAMP
    TIMESTAMP=$(date +"%Y%m%d%H%M%S")
    local BACKUP_FILE="${BACKUP_DIR}/${CONTAINER_NAME}_backup_${TIMESTAMP}.tar"

    echo_info "Backing up data of container: $CONTAINER_NAME to $BACKUP_FILE"
    podman export "$CONTAINER_NAME" -o "$BACKUP_FILE"

    echo_success "Backup completed: $BACKUP_FILE"
}

# Function to restore container data from backup
restore_container() {
    local CONTAINER_NAME="$1"
    local BACKUP_FILE="$2"

    if podman_container_exists "$CONTAINER_NAME"; then
        echo_error "Container $CONTAINER_NAME already exists. Remove it before restoring."
        exit 1
    fi

    if [ ! -f "$BACKUP_FILE" ]; then
        echo_error "Backup file $BACKUP_FILE does not exist."
        exit 1
    fi

    echo_info "Restoring container $CONTAINER_NAME from backup $BACKUP_FILE"
    podman import "$BACKUP_FILE" "$CONTAINER_NAME"

    echo_success "Container $CONTAINER_NAME restored from backup."
}

# Function to manage systemd services
manage_service() {
    local ACTION="$1"
    local CONTAINER_NAME="$2"

    if [ -z "$CONTAINER_NAME" ]; then
        echo_error "--image-name is required for service management."
        display_service_help
        exit 1
    fi

    local SERVICE_NAME="pm-${CONTAINER_NAME}.service"

    case "$ACTION" in
        start)
            echo_info "Starting systemd service: $SERVICE_NAME"
            sudo systemctl start "$SERVICE_NAME"
            echo_success "Service $SERVICE_NAME started."
            ;;
        stop)
            echo_info "Stopping systemd service: $SERVICE_NAME"
            sudo systemctl stop "$SERVICE_NAME"
            echo_success "Service $SERVICE_NAME stopped."
            ;;
        restart)
            echo_info "Restarting systemd service: $SERVICE_NAME"
            sudo systemctl restart "$SERVICE_NAME"
            echo_success "Service $SERVICE_NAME restarted."
            ;;
        status)
            echo_info "Status of systemd service: $SERVICE_NAME"
            sudo systemctl status "$SERVICE_NAME"
            ;;
        *)
            echo_error "Unknown service action: $ACTION"
            display_service_help
            exit 1
            ;;
    esac
}

# Function to check if a systemd service exists
is_systemd_service_present() {
    local CONTAINER_NAME="$1"
    local SERVICE_NAME="pm-${CONTAINER_NAME}.service"
    local SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"
    if [ -f "$SERVICE_FILE" ]; then
        return 0
    else
        return 1
    fi
}

# Function to launch the user-friendly UI
launch_ui() {
    while true; do
        local cmd
        cmd=$(dialog --clear \
            --backtitle "vroot UI" \
            --title "vroot - Podman Container Manager" \
            --menu "Choose an option:" 20 70 15 \
            1 "Create a new container" \
            2 "Enter an existing container" \
            3 "List containers" \
            4 "Remove a container" \
            5 "Backup a container" \
            6 "Restore a container" \
            7 "Manage container service" \
            8 "Exit" \
            3>&1 1>&2 2>&3)

        clear

        case $cmd in
            1)
                create_from_ui
                ;;
            2)
                enter_from_ui
                ;;
            3)
                list_from_ui
                ;;
            4)
                remove_from_ui
                ;;
            5)
                backup_from_ui
                ;;
            6)
                restore_from_ui
                ;;
            7)
                service_from_ui
                ;;
            8)
                echo_info "Exiting UI."
                exit 0
                ;;
            *)
                echo_error "Invalid option."
                ;;
        esac
    done
}

# Function to create a container via UI
create_from_ui() {
    # Prompt for base image
    BASE_IMAGE=$(dialog --inputbox "Enter base image:" 8 40 "$DEFAULT_BASE_IMAGE" 3>&1 1>&2 2>&3) || return
    if [ -z "$BASE_IMAGE" ]; then
        echo_warning "Base image not provided. Using default: $DEFAULT_BASE_IMAGE"
        BASE_IMAGE="$DEFAULT_BASE_IMAGE"
    fi

    # Prompt for port
    HOST_PORT=$(dialog --inputbox "Enter host port (leave empty for auto):" 8 40 "" 3>&1 1>&2 2>&3) || HOST_PORT=""
    if [ -n "$HOST_PORT" ]; then
        if ! [[ "$HOST_PORT" =~ ^[0-9]+$ ]] || [ "$HOST_PORT" -lt 1 ] || [ "$HOST_PORT" -gt 65535 ]; then
            echo_warning "Invalid port. Using default or auto-assigned port."
            HOST_PORT=""
        fi
    fi

    # Prompt for data directory
    CONTAINER_DIR=$(dialog --dselect "$DEFAULT_DATA_DIR" 10 50 3>&1 1>&2 2>&3) || CONTAINER_DIR="$DEFAULT_DATA_DIR"
    if [ -z "$CONTAINER_DIR" ]; then
        echo_warning "Directory not selected. Using default: $DEFAULT_DATA_DIR"
        CONTAINER_DIR="$DEFAULT_DATA_DIR"
    fi

    # Confirm directory exists or create it
    if [ ! -d "$CONTAINER_DIR" ]; then
        read -p "Directory $CONTAINER_DIR does not exist. Create it? (y/n): " CREATE_DIR
        if [[ "$CREATE_DIR" =~ ^[Yy]$ ]]; then
            mkdir -p "$CONTAINER_DIR"
            echo_info "Created directory: $CONTAINER_DIR"
        else
            echo_error "Directory selection is mandatory."
            return
        fi
    fi

    # Prompt for alias name
    ALIAS_NAME=$(dialog --inputbox "Enter alias name:" 8 40 "$DEFAULT_ALIAS" 3>&1 1>&2 2>&3) || ALIAS_NAME="$DEFAULT_ALIAS"
    if [ -z "$ALIAS_NAME" ]; then
        echo_warning "Alias name not provided. Using default: $DEFAULT_ALIAS"
        ALIAS_NAME="$DEFAULT_ALIAS"
    fi

    # Prompt for additional packages
    PACKAGES=$(dialog --inputbox "Enter comma-separated packages to install (optional):" 8 60 "" 3>&1 1>&2 2>&3) || PACKAGES=""
    PACKAGES="${PACKAGES// /}" # Remove spaces

    # Prompt for CPU limit
    CPU_LIMIT=$(dialog --inputbox "Enter CPU limit (default: $DEFAULT_CPU):" 8 40 "$DEFAULT_CPU" 3>&1 1>&2 2>&3) || CPU_LIMIT="$DEFAULT_CPU"
    if ! [[ "$CPU_LIMIT" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo_warning "Invalid CPU limit. Using default: $DEFAULT_CPU"
        CPU_LIMIT="$DEFAULT_CPU"
    fi

    # Prompt for Memory limit
    MEMORY_LIMIT=$(dialog --inputbox "Enter Memory limit (e.g., 512m, 1g) (default: $DEFAULT_MEMORY):" 8 40 "$DEFAULT_MEMORY" 3>&1 1>&2 2>&3) || MEMORY_LIMIT="$DEFAULT_MEMORY"
    if ! [[ "$MEMORY_LIMIT" =~ ^[0-9]+[mMgG]$ ]]; then
        echo_warning "Invalid Memory limit. Using default: $DEFAULT_MEMORY"
        MEMORY_LIMIT="$DEFAULT_MEMORY"
    fi

    create_container "$BASE_IMAGE" "$HOST_PORT" "$CONTAINER_DIR" "$ALIAS_NAME" "$PACKAGES" "$CPU_LIMIT" "$MEMORY_LIMIT"
}

# Function to enter a container via UI
enter_from_ui() {
    # List all containers
    CONTAINERS_ALL=$(podman ps -a --format "{{.Names}}")

    if [ -z "$CONTAINERS_ALL" ]; then
        echo_warning "No containers found."
        return
    fi

    # Prepare dialog menu options
    MENU_OPTIONS=()
    while IFS= read -r container; do
        STATUS=$(podman inspect -f '{{.State.Status}}' "$container")
        MENU_OPTIONS+=("$container" "$STATUS")
    done <<< "$CONTAINERS_ALL"

    SELECTED_CONTAINER=$(dialog --menu "Select a container to enter:" 20 60 15 "${MENU_OPTIONS[@]}" 3>&1 1>&2 2>&3) || return

    clear

    if [ -z "$SELECTED_CONTAINER" ]; then
        echo_warning "No container selected."
        return
    fi

    if podman_container_exists "$SELECTED_CONTAINER"; then
        # Start the container if it's not running
        local STATUS
        STATUS=$(podman inspect -f '{{.State.Status}}' "$SELECTED_CONTAINER")
        if [ "$STATUS" != "running" ]; then
            echo_info "Starting container: $SELECTED_CONTAINER"
            podman start "$SELECTED_CONTAINER"
        fi

        echo_info "Entering container: $SELECTED_CONTAINER"
        podman exec -it "$SELECTED_CONTAINER" /bin/bash
    else
        echo_error "Container $SELECTED_CONTAINER does not exist."
    fi
}

# Function to list containers via UI
list_from_ui() {
    local choice
    choice=$(dialog --menu "List Containers:" 15 50 4 \
        1 "List All Containers" \
        2 "List Running Containers" \
        3 "List Stopped Containers" \
        4 "Cancel" \
        3>&1 1>&2 2>&3) || return

    clear

    case $choice in
        1)
            CONTAINER_LIST=$(list_containers "all")
            ;;
        2)
            CONTAINER_LIST=$(list_containers "running")
            ;;
        3)
            CONTAINER_LIST=$(list_containers "stopped")
            ;;
        4)
            echo_info "Cancelled listing containers."
            return
            ;;
        *)
            echo_error "Invalid option."
            return
            ;;
    esac

    # Display the container list in a scrollable box
    dialog --title "Container List" --msgbox "$CONTAINER_LIST" 20 80
}

# Function to remove a container via UI
remove_from_ui() {
    # List all containers
    CONTAINERS_ALL=$(podman ps -a --format "{{.Names}}")

    if [ -z "$CONTAINERS_ALL" ]; then
        echo_warning "No containers found."
        return
    fi

    # Prepare dialog menu options
    MENU_OPTIONS=()
    while IFS= read -r container; do
        MENU_OPTIONS+=("$container" "")
    done <<< "$CONTAINERS_ALL"

    SELECTED_CONTAINER=$(dialog --menu "Select a container to remove:" 20 60 15 "${MENU_OPTIONS[@]}" 3>&1 1>&2 2>&3) || return

    clear

    if [ -z "$SELECTED_CONTAINER" ]; then
        echo_warning "No container selected."
        return
    fi

    read -p "Are you sure you want to remove container '$SELECTED_CONTAINER'? (y/n): " CONFIRM
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        read -p "Force removal? (y/n): " FORCE_CONFIRM
        if [[ "$FORCE_CONFIRM" =~ ^[Yy]$ ]]; then
            remove_container "$SELECTED_CONTAINER" "true"
        else
            remove_container "$SELECTED_CONTAINER" "false"
        fi
    else
        echo_info "Container removal cancelled."
    fi
}

# Function to backup a container via UI
backup_from_ui() {
    # List all containers
    CONTAINERS_ALL=$(podman ps -a --format "{{.Names}}")

    if [ -z "$CONTAINERS_ALL" ]; then
        echo_warning "No containers found."
        return
    fi

    # Prepare dialog menu options
    MENU_OPTIONS=()
    while IFS= read -r container; do
        MENU_OPTIONS+=("$container" "")
    done <<< "$CONTAINERS_ALL"

    SELECTED_CONTAINER=$(dialog --menu "Select a container to backup:" 20 60 15 "${MENU_OPTIONS[@]}" 3>&1 1>&2 2>&3) || return

    clear

    if [ -z "$SELECTED_CONTAINER" ]; then
        echo_warning "No container selected."
        return
    fi

    # Prompt for backup directory
    BACKUP_DIR=$(dialog --dselect "$HOME/backups" 10 50 3>&1 1>&2 2>&3) || BACKUP_DIR="$HOME/backups"
    if [ -z "$BACKUP_DIR" ]; then
        echo_warning "Backup directory not selected. Using default: $HOME/backups"
        BACKUP_DIR="$HOME/backups"
    fi

    # Confirm directory exists or create it
    if [ ! -d "$BACKUP_DIR" ]; then
        read -p "Directory $BACKUP_DIR does not exist. Create it? (y/n): " CREATE_DIR
        if [[ "$CREATE_DIR" =~ ^[Yy]$ ]]; then
            mkdir -p "$BACKUP_DIR"
            echo_info "Created directory: $BACKUP_DIR"
        else
            echo_error "Backup directory selection is mandatory."
            return
        fi
    fi

    backup_container "$SELECTED_CONTAINER" "$BACKUP_DIR"
}

# Function to restore a container via UI
restore_from_ui() {
    # Prompt for container name
    CONTAINER_NAME=$(dialog --inputbox "Enter name for the restored container:" 8 40 "" 3>&1 1>&2 2>&3) || return
    if [ -z "$CONTAINER_NAME" ]; then
        echo_error "Container name is required for restoration."
        return
    fi

    # Check if container with the same name exists
    if podman_container_exists "$CONTAINER_NAME"; then
        echo_error "A container with name '$CONTAINER_NAME' already exists. Choose a different name."
        return
    fi

    # Prompt for backup file
    BACKUP_FILE=$(dialog --fselect "$HOME/backups/" 15 60 3>&1 1>&2 2>&3) || return
    if [ -z "$BACKUP_FILE" ]; then
        echo_error "Backup file is required for restoration."
        return
    fi

    restore_container "$CONTAINER_NAME" "$BACKUP_FILE"
}

# Function to manage services via UI
service_from_ui() {
    # Prompt for subcommand
    ACTION=$(dialog --menu "Select service action:" 15 50 4 \
        1 "Start Service" \
        2 "Stop Service" \
        3 "Restart Service" \
        4 "Check Service Status" \
        5 "Cancel" \
        3>&1 1>&2 2>&3) || return

    clear

    case $ACTION in
        1)
            ACTION_CMD="start"
            ;;
        2)
            ACTION_CMD="stop"
            ;;
        3)
            ACTION_CMD="restart"
            ;;
        4)
            ACTION_CMD="status"
            ;;
        5)
            echo_info "Service management cancelled."
            return
            ;;
        *)
            echo_error "Invalid option."
            return
            ;;
    esac

    # List all containers
    CONTAINERS_ALL=$(podman ps -a --format "{{.Names}}")

    if [ -z "$CONTAINERS_ALL" ]; then
        echo_warning "No containers found."
        return
    fi

    # Prepare dialog menu options
    MENU_OPTIONS=()
    while IFS= read -r container; do
        MENU_OPTIONS+=("$container" "")
    done <<< "$CONTAINERS_ALL"

    SELECTED_CONTAINER=$(dialog --menu "Select a container for service action:" 20 60 15 "${MENU_OPTIONS[@]}" 3>&1 1>&2 2>&3) || return

    clear

    if [ -z "$SELECTED_CONTAINER" ]; then
        echo_warning "No container selected."
        return
    fi

    # Check if service exists; if not, prompt to create it
    if ! is_systemd_service_present "$SELECTED_CONTAINER"; then
        echo_warning "Systemd service for container $SELECTED_CONTAINER does not exist."
        read -p "Do you want to create it? (y/n): " CREATE_SERVICE
        if [[ "$CREATE_SERVICE" =~ ^[Yy]$ ]]; then
            create_systemd_service "$SELECTED_CONTAINER"
        else
            echo_info "Service management cancelled."
            return
        fi
    fi

    manage_service "$ACTION_CMD" "$SELECTED_CONTAINER"
}

# Function to handle unknown commands
unknown_command() {
    echo_error "Unknown command: $1"
    display_help
    exit 1
}

# ------------------------------- Main Script ----------------------------------

# Load configuration
load_config

# Check for root privileges for certain operations
if [ "$EUID" -ne 0 ]; then
    SUDO='sudo'
else
    SUDO=''
fi

# Check dependencies
check_dependencies

# If no arguments are provided, launch UI
if [ $# -eq 0 ]; then
    launch_ui
    exit 0
fi

# Parse subcommand
SUBCOMMAND="$1"
shift

case "$SUBCOMMAND" in
    create)
        # Parse options for create
        OPTIONS=$(getopt -o h --long help,base-image:,port:,dir:,alias:,packages:,cpu:,memory: -n 'vroot create' -- "$@")
        if [ $? != 0 ]; then
            echo_error "Failed to parse create options."
            display_create_help
            exit 1
        fi

        eval set -- "$OPTIONS"

        # Initialize variables with default values
        CREATE_BASE_IMAGE="$DEFAULT_BASE_IMAGE"
        CREATE_PORT=""
        CREATE_DIR="$DEFAULT_DATA_DIR"
        CREATE_ALIAS="$DEFAULT_ALIAS"
        CREATE_PACKAGES="$(IFS=,; echo "${DEFAULT_PACKAGES[*]}")"
        CREATE_CPU="$DEFAULT_CPU"
        CREATE_MEMORY="$DEFAULT_MEMORY"

        while true; do
            case "$1" in
                --base-image)
                    CREATE_BASE_IMAGE="$2"
                    shift 2
                    ;;
                --port)
                    CREATE_PORT="$2"
                    shift 2
                    ;;
                --dir)
                    CREATE_DIR="$2"
                    shift 2
                    ;;
                --alias)
                    CREATE_ALIAS="$2"
                    shift 2
                    ;;
                --packages)
                    CREATE_PACKAGES="$2"
                    shift 2
                    ;;
                --cpu)
                    CREATE_CPU="$2"
                    shift 2
                    ;;
                --memory)
                    CREATE_MEMORY="$2"
                    shift 2
                    ;;
                -h|--help)
                    display_create_help
                    exit 0
                    ;;
                --)
                    shift
                    break
                    ;;
                *)
                    echo_error "Unknown option: $1"
                    display_create_help
                    exit 1
                    ;;
            esac
        done

        create_container "$CREATE_BASE_IMAGE" "$CREATE_PORT" "$CREATE_DIR" "$CREATE_ALIAS" "$CREATE_PACKAGES" "$CREATE_CPU" "$CREATE_MEMORY"
        ;;
    enter)
        # Parse options for enter
        OPTIONS=$(getopt -o h --long help,image-name: -n 'vroot enter' -- "$@")
        if [ $? != 0 ]; then
            echo_error "Failed to parse enter options."
            display_enter_help
            exit 1
        fi

        eval set -- "$OPTIONS"

        ENTER_IMAGE_NAME=""

        while true; do
            case "$1" in
                --image-name)
                    ENTER_IMAGE_NAME="$2"
                    shift 2
                    ;;
                -h|--help)
                    display_enter_help
                    exit 0
                    ;;
                --)
                    shift
                    break
                    ;;
                *)
                    echo_error "Unknown option: $1"
                    display_enter_help
                    exit 1
                    ;;
            esac
        done

        if [ -z "$ENTER_IMAGE_NAME" ]; then
            echo_error "--image-name is required for the enter command."
            display_enter_help
            exit 1
        fi

        if podman_container_exists "$ENTER_IMAGE_NAME"; then
            # Start the container if it's not running
            local STATUS
            STATUS=$(podman inspect -f '{{.State.Status}}' "$ENTER_IMAGE_NAME")
            if [ "$STATUS" != "running" ]; then
                echo_info "Starting container: $ENTER_IMAGE_NAME"
                podman start "$ENTER_IMAGE_NAME"
            fi

            podman exec -it "$ENTER_IMAGE_NAME" /bin/bash
        else
            echo_error "Container $ENTER_IMAGE_NAME does not exist."
            exit 1
        fi
        ;;
    list)
        # Parse options for list
        OPTIONS=$(getopt -o h --long help,all,running,stopped -n 'vroot list' -- "$@")
        if [ $? != 0 ]; then
            echo_error "Failed to parse list options."
            display_list_help
            exit 1
        fi

        eval set -- "$OPTIONS"

        LIST_FILTER=""

        while true; do
            case "$1" in
                --all)
                    LIST_FILTER="all"
                    shift
                    ;;
                --running)
                    LIST_FILTER="running"
                    shift
                    ;;
                --stopped)
                    LIST_FILTER="stopped"
                    shift
                    ;;
                -h|--help)
                    display_list_help
                    exit 1
                    ;;
                --)
                    shift
                    break
                    ;;
                *)
                    echo_error "Unknown option: $1"
                    display_list_help
                    exit 1
                    ;;
            esac
        done

        CONTAINER_LIST=$(list_containers "$LIST_FILTER")
        dialog --title "Container List" --msgbox "$CONTAINER_LIST" 20 80
        ;;
    remove)
        # Parse options for remove
        OPTIONS=$(getopt -o h --long help,image-name:,force -n 'vroot remove' -- "$@")
        if [ $? != 0 ]; then
            echo_error "Failed to parse remove options."
            display_remove_help
            exit 1
        fi

        eval set -- "$OPTIONS"

        REMOVE_IMAGE_NAME=""
        REMOVE_FORCE="false"

        while true; do
            case "$1" in
                --image-name)
                    REMOVE_IMAGE_NAME="$2"
                    shift 2
                    ;;
                --force)
                    REMOVE_FORCE="true"
                    shift
                    ;;
                -h|--help)
                    display_remove_help
                    exit 0
                    ;;
                --)
                    shift
                    break
                    ;;
                *)
                    echo_error "Unknown option: $1"
                    display_remove_help
                    exit 1
                    ;;
            esac
        done

        if [ -z "$REMOVE_IMAGE_NAME" ]; then
            echo_error "--image-name is required for the remove command."
            display_remove_help
            exit 1
        fi

        remove_container "$REMOVE_IMAGE_NAME" "$REMOVE_FORCE"
        ;;
    backup)
        # Parse options for backup
        OPTIONS=$(getopt -o h --long help,image-name:,backup-dir: -n 'vroot backup' -- "$@")
        if [ $? != 0 ]; then
            echo_error "Failed to parse backup options."
            display_backup_help
            exit 1
        fi

        eval set -- "$OPTIONS"

        BACKUP_IMAGE_NAME=""
        BACKUP_DIR="$HOME/backups"

        while true; do
            case "$1" in
                --image-name)
                    BACKUP_IMAGE_NAME="$2"
                    shift 2
                    ;;
                --backup-dir)
                    BACKUP_DIR="$2"
                    shift 2
                    ;;
                -h|--help)
                    display_backup_help
                    exit 1
                    ;;
                --)
                    shift
                    break
                    ;;
                *)
                    echo_error "Unknown option: $1"
                    display_backup_help
                    exit 1
                    ;;
            esac
        done

        if [ -z "$BACKUP_IMAGE_NAME" ]; then
            echo_error "--image-name is required for the backup command."
            display_backup_help
            exit 1
        fi

        backup_container "$BACKUP_IMAGE_NAME" "$BACKUP_DIR"
        ;;
    restore)
        # Parse options for restore
        OPTIONS=$(getopt -o h --long help,image-name:,backup-file: -n 'vroot restore' -- "$@")
        if [ $? != 0 ]; then
            echo_error "Failed to parse restore options."
            display_restore_help
            exit 1
        fi

        eval set -- "$OPTIONS"

        RESTORE_IMAGE_NAME=""
        RESTORE_BACKUP_FILE=""

        while true; do
            case "$1" in
                --image-name)
                    RESTORE_IMAGE_NAME="$2"
                    shift 2
                    ;;
                --backup-file)
                    RESTORE_BACKUP_FILE="$2"
                    shift 2
                    ;;
                -h|--help)
                    display_restore_help
                    exit 1
                    ;;
                --)
                    shift
                    break
                    ;;
                *)
                    echo_error "Unknown option: $1"
                    display_restore_help
                    exit 1
                    ;;
            esac
        done

        if [ -z "$RESTORE_IMAGE_NAME" ] || [ -z "$RESTORE_BACKUP_FILE" ]; then
            echo_error "--image-name and --backup-file are required for the restore command."
            display_restore_help
            exit 1
        fi

        restore_container "$RESTORE_IMAGE_NAME" "$RESTORE_BACKUP_FILE"
        ;;
    service)
        # Parse subcommand and options for service
        SERVICE_SUBCOMMAND="$1"
        shift

        OPTIONS=$(getopt -o h --long help,image-name: -n 'vroot service' -- "$@")
        if [ $? != 0 ]; then
            echo_error "Failed to parse service options."
            display_service_help
            exit 1
        fi

        eval set -- "$OPTIONS"

        SERVICE_IMAGE_NAME=""

        while true; do
            case "$1" in
                --image-name)
                    SERVICE_IMAGE_NAME="$2"
                    shift 2
                    ;;
                -h|--help)
                    display_service_help
                    exit 1
                    ;;
                --)
                    shift
                    break
                    ;;
                *)
                    echo_error "Unknown option: $1"
                    display_service_help
                    exit 1
                    ;;
            esac
        done

        if [ -z "$SERVICE_IMAGE_NAME" ]; then
            echo_error "--image-name is required for service management."
            display_service_help
            exit 1
        fi

        # Check if service exists; if not, prompt to create it
        if ! is_systemd_service_present "$SERVICE_IMAGE_NAME"; then
            echo_warning "Systemd service for container $SERVICE_IMAGE_NAME does not exist."
            read -p "Do you want to create it? (y/n): " CREATE_SERVICE
            if [[ "$CREATE_SERVICE" =~ ^[Yy]$ ]]; then
                create_systemd_service "$SERVICE_IMAGE_NAME"
            else
                echo_info "Service management cancelled."
                exit 0
            fi
        fi

        manage_service "$SERVICE_SUBCOMMAND" "$SERVICE_IMAGE_NAME"
        ;;
    ui)
        launch_ui
        ;;
    help|--help|-h)
        display_help
        exit 0
        ;;
    *)
        unknown_command "$SUBCOMMAND"
        ;;
esac

exit 0
