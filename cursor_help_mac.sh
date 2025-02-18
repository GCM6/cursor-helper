#!/bin/bash

# Set error handling
set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Get current user
get_current_user() {
    if [ "$EUID" -eq 0 ]; then
        echo "$SUDO_USER"
    else
        echo "$USER"
    fi
}

CURRENT_USER=$(get_current_user)
if [ -z "$CURRENT_USER" ]; then
    log_error "Unable to get username"
    exit 1
fi

# Define config file paths
STORAGE_FILE="$HOME/Library/Application Support/Cursor/User/globalStorage/storage.json"
BACKUP_DIR="$HOME/Library/Application Support/Cursor/User/globalStorage/backups"

# Define Cursor app path
CURSOR_APP_PATH="/Applications/Cursor.app"

# Check permissions
check_permissions() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run this script with sudo"
        echo "Example: sudo $0"
        exit 1
    fi
}

# Check and kill Cursor process
check_and_kill_cursor() {
    log_info "Checking Cursor process..."
    
    local attempt=1
    local max_attempts=5
    
    # Function: Get process details
    get_process_details() {
        local process_name="$1"
        log_debug "Getting process details for $process_name:"
        ps aux | grep -i "$process_name" | grep -v grep
    }
    
    while [ $attempt -le $max_attempts ]; do
        CURSOR_PIDS=$(pgrep -i "cursor" || true)
        
        if [ -z "$CURSOR_PIDS" ]; then
            log_info "No running Cursor process found"
            return 0
        fi
        
        log_warn "Found running Cursor process"
        get_process_details "cursor"
        
        log_warn "Attempting to close Cursor process..."
        
        if [ $attempt -eq $max_attempts ]; then
            log_warn "Attempting force kill..."
            kill -9 $CURSOR_PIDS 2>/dev/null || true
        else
            kill $CURSOR_PIDS 2>/dev/null || true
        fi
        
        sleep 1
        
        if ! pgrep -i "cursor" > /dev/null; then
            log_info "Cursor process successfully closed"
            return 0
        fi
        
        log_warn "Waiting for process to close, attempt $attempt/$max_attempts..."
        ((attempt++))
    done
    
    log_error "Unable to close Cursor process after $max_attempts attempts"
    get_process_details "cursor"
    log_error "Please close the process manually and try again"
    exit 1
}

# Backup system ID
backup_system_id() {
    log_info "Backing up system ID..."
    local system_id_file="$BACKUP_DIR/system_id.backup_$(date +%Y%m%d_%H%M%S)"
    
    # Get and backup IOPlatformExpertDevice info
    {
        echo "# Original System ID Backup" > "$system_id_file"
        echo "## IOPlatformExpertDevice Info:" >> "$system_id_file"
        ioreg -rd1 -c IOPlatformExpertDevice >> "$system_id_file"
        
        chmod 444 "$system_id_file"
        chown "$CURRENT_USER" "$system_id_file"
        log_info "System ID backed up to: $system_id_file"
    } || {
        log_error "Failed to backup system ID"
        return 1
    }
}

# Backup config file
backup_config() {
    if [ ! -f "$STORAGE_FILE" ]; then
        log_warn "Config file does not exist, skipping backup"
        return 0
    }
    
    mkdir -p "$BACKUP_DIR"
    local backup_file="$BACKUP_DIR/storage.json.backup_$(date +%Y%m%d_%H%M%S)"
    
    if cp "$STORAGE_FILE" "$backup_file"; then
        chmod 644 "$backup_file"
        chown "$CURRENT_USER" "$backup_file"
        log_info "Config backed up to: $backup_file"
    else
        log_error "Backup failed"
        exit 1
    fi
}

# Generate random ID
generate_random_id() {
    # Generate 32 bytes (64 hex characters) random number
    openssl rand -hex 32
}

# Generate random UUID
generate_uuid() {
    uuidgen | tr '[:upper:]' '[:lower:]'
}

# Modify existing file
modify_or_add_config() {
    local key="$1"
    local value="$2"
    local file="$3"
    
    if [ ! -f "$file" ]; then
        log_error "File does not exist: $file"
        return 1
    }
    
    # Ensure file is writable
    chmod 644 "$file" || {
        log_error "Unable to modify file permissions: $file"
        return 1
    }
    
    # Create temp file
    local temp_file=$(mktemp)
    
    # Check if key exists
    if grep -q "\"$key\":" "$file"; then
        # Key exists, perform replacement
        sed "s/\"$key\":[[:space:]]*\"[^\"]*\"/\"$key\": \"$value\"/" "$file" > "$temp_file" || {
            log_error "Failed to modify config: $key"
            rm -f "$temp_file"
            return 1
        }
    else
        # Key doesn't exist, add new key-value pair
        sed "s/}$/,\n    \"$key\": \"$value\"\n}/" "$file" > "$temp_file" || {
            log_error "Failed to add config: $key"
            rm -f "$temp_file"
            return 1
        }
    fi
    
    # Check if temp file is empty
    if [ ! -s "$temp_file" ]; then
        log_error "Generated temp file is empty"
        rm -f "$temp_file"
        return 1
    }
    
    # Use cat to replace original file content
    cat "$temp_file" > "$file" || {
        log_error "Unable to write to file: $file"
        rm -f "$temp_file"
        return 1
    }
    
    rm -f "$temp_file"
    
    # Restore file permissions
    chmod 444 "$file"
    
    return 0
}

# Generate new config
generate_new_config() {
  
    # Modify system ID
    log_info "Modifying system ID..."
    
    # Backup current system ID
    backup_system_id
    
    # Generate new system UUID
    local new_system_uuid=$(uuidgen)
    
    # Modify system UUID
    sudo nvram SystemUUID="$new_system_uuid"
    printf "${YELLOW}System UUID updated to: $new_system_uuid${NC}\n"
    printf "${YELLOW}Please restart system for changes to take effect${NC}\n"
    
    # Convert auth0|user_ to hex byte array
    local prefix_hex=$(echo -n "auth0|user_" | xxd -p)
    local random_part=$(generate_random_id)
    local machine_id="${prefix_hex}${random_part}"
    
    local mac_machine_id=$(generate_random_id)
    local device_id=$(generate_uuid | tr '[:upper:]' '[:lower:]')
    local sqm_id="{$(generate_uuid | tr '[:lower:]' '[:upper:]')}"
    
    log_info "Modifying config file..."
    # Check if config file exists
    if [ ! -f "$STORAGE_FILE" ]; then
        log_error "Config file not found: $STORAGE_FILE"
        log_warn "Please install and run Cursor once before using this script"
        exit 1
    }
    
    # Ensure config directory exists
    mkdir -p "$(dirname "$STORAGE_FILE")" || {
        log_error "Unable to create config directory"
        exit 1
    }
    
    # If file doesn't exist, create basic JSON structure
    if [ ! -s "$STORAGE_FILE" ]; then
        echo '{}' > "$STORAGE_FILE" || {
            log_error "Unable to initialize config file"
            exit 1
        }
    }
    
    # Modify existing file
    modify_or_add_config "telemetry.machineId" "$machine_id" "$STORAGE_FILE" || exit 1
    modify_or_add_config "telemetry.macMachineId" "$mac_machine_id" "$STORAGE_FILE" || exit 1
    modify_or_add_config "telemetry.devDeviceId" "$device_id" "$STORAGE_FILE" || exit 1
    modify_or_add_config "telemetry.sqmId" "$sqm_id" "$STORAGE_FILE" || exit 1
    
    # Set file permissions and owner
    chmod 444 "$STORAGE_FILE"  # Change to read-only
    chown "$CURRENT_USER" "$STORAGE_FILE"
    
    # Verify permission settings
    if [ -w "$STORAGE_FILE" ]; then
        log_warn "Unable to set read-only permission, trying alternative method..."
        chattr +i "$STORAGE_FILE" 2>/dev/null || true
    else
        log_info "Successfully set file to read-only"
    fi
    
    echo
    log_info "Updated config: $STORAGE_FILE"
    log_debug "machineId: $machine_id"
    log_debug "macMachineId: $mac_machine_id"
    log_debug "devDeviceId: $device_id"
    log_debug "sqmId: $sqm_id"
}

# Modify Cursor app files (safe mode)
modify_cursor_app_files() {
    log_info "Safely modifying Cursor app files..."
    
    # Verify app exists
    if [ ! -d "$CURSOR_APP_PATH" ]; then
        log_error "Cursor.app not found, please verify install path: $CURSOR_APP_PATH"
        return 1
    }

    # Define target files
    local target_files=(
        "${CURSOR_APP_PATH}/Contents/Resources/app/out/main.js"
        "${CURSOR_APP_PATH}/Contents/Resources/app/out/vs/code/node/cliProcessMain.js"
    )
    
    # Check if files exist and need modification
    local need_modification=false
    local missing_files=false
    
    for file in "${target_files[@]}"; do
        if [ ! -f "$file" ]; then
            log_warn "File does not exist: ${file/$CURSOR_APP_PATH\//}"
            missing_files=true
            continue
        }
        
        if ! grep -q "return crypto.randomUUID()" "$file" 2>/dev/null; then
            log_info "File needs modification: ${file/$CURSOR_APP_PATH\//}"
            need_modification=true
            break
        else
            log_info "File already modified: ${file/$CURSOR_APP_PATH\//}"
        fi
    done
    
    # Exit if all files are modified or missing
    if [ "$missing_files" = true ]; then
        log_error "Some target files are missing, please verify Cursor installation"
        return 1
    fi
    
    if [ "$need_modification" = false ]; then
        log_info "All target files already modified, no action needed"
        return 0
    fi

    # Create temp working directory
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local temp_dir="/tmp/cursor_reset_${timestamp}"
    local temp_app="${temp_dir}/Cursor.app"
    local backup_app="/tmp/Cursor.app.backup_${timestamp}"
    
    # Clean up existing temp directory
    if [ -d "$temp_dir" ]; then
        log_info "Cleaning up existing temp directory..."
        rm -rf "$temp_dir"
    fi
    
    # Create new temp directory
    mkdir -p "$temp_dir" || {
        log_error "Unable to create temp directory: $temp_dir"
        return 1
    }

    # Backup original app
    log_info "Backing up original app..."
    cp -R "$CURSOR_APP_PATH" "$backup_app" || {
        log_error "Unable to create app backup"
        rm -rf "$temp_dir"
        return 1
    }

    # Copy app to temp directory
    log_info "Creating temp working copy..."
    cp -R "$CURSOR_APP_PATH" "$temp_dir" || {
        log_error "Unable to copy app to temp directory"
        rm -rf "$temp_dir" "$backup_app"
        return 1
    }

    # Ensure temp directory permissions are correct
    chown -R "$CURRENT_USER:staff" "$temp_dir"
    chmod -R 755 "$temp_dir"

    # Remove signature (enhance compatibility)
    log_info "Removing app signature..."
    codesign --remove-signature "$temp_app" || {
        log_warn "Failed to remove app signature"
    }

    # Remove signatures for all related components
    local components=(
        "$temp_app/Contents/Frameworks/Cursor Helper.app"
        "$temp_app/Contents/Frameworks/Cursor Helper (GPU).app"
        "$temp_app/Contents/Frameworks/Cursor Helper (Plugin).app"
        "$temp_app/Contents/Frameworks/Cursor Helper (Renderer).app"
    )

    for component in "${components[@]}"; do
        if [ -e "$component" ]; then
            log_info "Removing signature: $component"
            codesign --remove-signature "$component" || {
                log_warn "Failed to remove component signature: $component"
            }
        fi
    done
    
    # Modify target files
    local modified_count=0
    local files=(
        "${temp_app}/Contents/Resources/app/out/main.js"
        "${temp_app}/Contents/Resources/app/out/vs/code/node/cliProcessMain.js"
    )
    
    for file in "${files[@]}"; do
        if [ ! -f "$file" ]; then
            log_warn "File does not exist: ${file/$temp_dir\//}"
            continue
        }
        
        log_debug "Processing file: ${file/$temp_dir\//}"
        
        # Create file backup
        cp "$file" "${file}.bak" || {
            log_error "Unable to create file backup: ${file/$temp_dir\//}"
            continue
        }

        # Read file content
        local content=$(cat "$file")
        
        # Find IOPlatformUUID position
        local uuid_pos=$(printf "%s" "$content" | grep -b -o "IOPlatformUUID" | cut -d: -f1)
        if [ -z "$uuid_pos" ]; then
            log_warn "IOPlatformUUID not found in $file"
            continue
        }

        # Search for switch before UUID position
        local before_uuid=${content:0:$uuid_pos}
        local switch_pos=$(printf "%s" "$before_uuid" | grep -b -o "switch" | tail -n1 | cut -d: -f1)
        if [ -z "$switch_pos" ]; then
            log_warn "switch keyword not found in $file"
            continue
        }

        # Build new file content
        if printf "%sreturn crypto.randomUUID();\n%s" "${content:0:$switch_pos}" "${content:$switch_pos}" > "$file"; then
            ((modified_count++))
            log_info "Successfully modified file: ${file/$temp_dir\//}"
        else
            log_error "File write failed: ${file/$temp_dir\//}"
            mv "${file}.bak" "$file"
        fi
        
        # Clean up backup
        rm -f "${file}.bak"
    done
    
    if [ "$modified_count" -eq 0 ]; then
        log_error "Failed to modify any files"
        rm -rf "$temp_dir"
        return 1
    }
    
    # Re-sign app (with retry mechanism)
    local max_retry=3
    local retry_count=0
    local sign_success=false
    
    while [ $retry_count -lt $max_retry ]; do
        ((retry_count++))
        log_info "Attempting to sign (attempt $retry_count)..."
        
        # Use more detailed signing parameters
        if codesign --sign - --force --deep --preserve-metadata=entitlements,identifier,flags "$temp_app" 2>&1 | tee /tmp/codesign.log; then
            # Verify signature
            if codesign --verify -vvvv "$temp_app" 2>/dev/null; then
                sign_success=true
                log_info "App signature verification passed"
                break
            else
                log_warn "Signature verification failed, error log:"
                cat /tmp/codesign.log
            fi
        else
            log_warn "Signing failed, error log:"
            cat /tmp/codesign.log
        fi
        
        sleep 1
    done

    if ! $sign_success; then
        log_error "Failed to complete signing after $max_retry attempts"
        log_error "Please manually execute the following command to complete signing:"
        echo -e "${BLUE}sudo codesign --sign - --force --deep '${temp_app}'${NC}"
        echo -e "${YELLOW}After completion, please manually copy the app to the original path:${NC}"
        echo -e "${BLUE}sudo cp -R '${temp_app}' '/Applications/'${NC}"
        log_info "Temp files retained at: ${temp_dir}"
        return 1
    fi

    # Replace original app
    log_info "Installing modified app..."
    if ! sudo rm -rf "$CURSOR_APP_PATH" || ! sudo cp -R "$temp_app" "/Applications/"; then
        log_error "App replacement failed, restoring..."
        sudo rm -rf "$CURSOR_APP_PATH"
        sudo cp -R "$backup_app" "$CURSOR_APP_PATH"
        rm -rf "$temp_dir" "$backup_app"
        return 1
    fi
    
    # Clean up temp files
    rm -rf "$temp_dir" "$backup_app"
    
    # Set permissions
    sudo chown -R "$CURRENT_USER:staff" "$CURSOR_APP_PATH"
    sudo chmod -R 755 "$CURSOR_APP_PATH"
    
    log_info "Cursor app files modification complete! Original backup at: ${backup_app/$HOME/\~}"
    return 0
}

# Show file tree structure
show_file_tree() {
    local base_dir=$(dirname "$STORAGE_FILE")
    echo
    log_info "File structure:"
    echo -e "${BLUE}$base_dir${NC}"
    echo "├── globalStorage"
    echo "│   ├── storage.json (Modified)"
    echo "│   └── backups"
    
    # List backup files
    if [ -d "$BACKUP_DIR" ]; then
        local backup_files=("$BACKUP_DIR"/*)
        if [ ${#backup_files[@]} -gt 0 ]; then
            for file in "${backup_files[@]}"; do
                if [ -f "$file" ]; then
                    echo "│       └── $(basename "$file")"
                fi
            done
        else
            echo "│       └── (Empty)"
        fi
    fi
    echo
}

# Disable auto update
disable_auto_update() {
    local updater_path="$HOME/Library/Application Support/Caches/cursor-updater"
    
    echo
    log_info "Disabling Cursor auto-update..."
    echo -e "${YELLOW}To restore auto-update, manually delete the file:${NC}"
    echo -e "${BLUE}$updater_path${NC}"
    echo
    
    # Try automatic execution
    if sudo rm -rf "$updater_path" && \
       sudo touch "$updater_path" && \
       sudo chmod 444 "$updater_path"; then
        log_info "Successfully disabled auto-update"
        echo
        log_info "Verification method:"
        echo "Run command: ls -l \"$updater_path\""
        echo "Confirm file permissions show as: r--r--r--"
    else
        log_error "Automatic setup failed, please manually execute the following commands:"
        echo
        echo -e "${BLUE}sudo rm -rf \"$updater_path\" && sudo touch \"$updater_path\" && sudo chmod 444 \"$updater_path\"${NC}"
    fi
    
    echo
    log_info "Please restart Cursor after completion"
}

# Generate random MAC address
generate_random_mac() {
    # Generate random MAC address, keeping second bit of first byte as 0 (ensure unicast)
    printf '02:%02x:%02x:%02x:%02x:%02x' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256))
}

# Get network interface list
get_network_interfaces() {
    networksetup -listallhardwareports | awk '/Hardware Port|Ethernet Address/ {print $NF}' | paste - - | grep -v 'N/A'
}

# Backup MAC addresses
backup_mac_addresses() {
    log_info "Backing up MAC addresses..."
    local backup_file="$BACKUP_DIR/mac_addresses.backup_$(date +%Y%m%d_%H%M%S)"
    
    {
        echo "# Original MAC Addresses Backup - $(date)" > "$backup_file"
        echo "## Network Interfaces:" >> "$backup_file"
        networksetup -listallhardwareports >> "$backup_file"
        
        chmod 444 "$backup_file"
        chown "$CURRENT_USER" "$backup_file"
        log_info "MAC addresses backed up to: $backup_file"
    } || {
        log_error "Failed to backup MAC addresses"
        return 1
    }
}

# Modify MAC address
modify_mac_address() {
    log_info "Getting network interface information..."
    
    # Backup current MAC addresses
    backup_mac_addresses
    
    # Get all network interfaces
    local interfaces=$(get_network_interfaces)
    
    if [ -z "$interfaces" ]; then
        log_error "No available network interfaces found"
        return 1
    fi
    
    echo
    log_info "Found following network interfaces:"
    echo "$interfaces" | nl -w2 -s') '
    echo
    
    echo -n "Please select interface number (press Enter to skip): "
    read -r choice
    
    if [ -z "$choice" ]; then
        log_info "Skipping MAC address modification"
        return 0
    fi
    
    # Get selected interface name
    local selected_interface=$(echo "$interfaces" | sed -n "${choice}p" | awk '{print $1}')
    
    if [ -z "$selected_interface" ]; then
        log_error "Invalid selection"
        return 1
    fi
    
    # Generate new MAC address
    local new_mac=$(generate_random_mac)
    
    log_info "Modifying MAC address for interface $selected_interface..."
    
    # Disable network interface
    sudo ifconfig "$selected_interface" down || {
        log_error "Unable to disable network interface"
        return 1
    }
    
    # Modify MAC address
    if sudo ifconfig "$selected_interface" ether "$new_mac"; then
        # Re-enable network interface
        sudo ifconfig "$selected_interface" up
        log_info "Successfully changed MAC address to: $new_mac"
        echo
        log_warn "Note: MAC address change may require network reconnection to take effect"
    else
        log_error "Failed to modify MAC address"
        # Try to restore network interface
        sudo ifconfig "$selected_interface" up
        return 1
    fi
}

# New restore feature option
restore_feature() {
    # Check if backup directory exists
    if [ ! -d "$BACKUP_DIR" ]; then
        log_warn "Backup directory does not exist"
        return 1
    }

    # Use find command to get backup file list and store in array
    backup_files=()
    while IFS= read -r file; do
        [ -f "$file" ] && backup_files+=("$file")
    done < <(find "$BACKUP_DIR" -name "*.backup_*" -type f 2>/dev/null | sort)
    
    # Check if backup files found
    if [ ${#backup_files[@]} -eq 0 ]; then
        log_warn "No backup files found"
        return 1
    fi
    
    echo
    log_info "Available backup files:"
    echo "0) Exit (Default)"
    
    # Display backup file list
    for i in "${!backup_files[@]}"; do
        echo "$((i+1))) $(basename "${backup_files[$i]}")"
    done
    
    echo
    echo -n "Please select backup file number [0-${#backup_files[@]}] (Default: 0): "
    read -r choice
    
    # Handle user input
    if [ -z "$choice" ] || [ "$choice" = "0" ]; then
        log_info "Skipping restore operation"
        return 0
    fi
    
    # Validate input
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -gt "${#backup_files[@]}" ]; then
        log_error "Invalid selection"
        return 1
    fi
    
    # Get selected backup file
    local selected_backup="${backup_files[$((choice-1))]}"
    
    # Verify file existence and readability
    if [ ! -f "$selected_backup" ] || [ ! -r "$selected_backup" ]; then
        log_error "Unable to access selected backup file"
        return 1
    fi
    
    # Try to restore config
    if cp "$selected_backup" "$STORAGE_FILE"; then
        chmod 644 "$STORAGE_FILE"
        chown "$CURRENT_USER" "$STORAGE_FILE"
        log_info "Config restored from backup file: $(basename "$selected_backup")"
        return 0
    else
        log_error "Failed to restore config"
        return 1
    fi
}

# Main function
main() {
    
    # New environment check
    if [[ $(uname) != "Darwin" ]]; then
        log_error "This script only supports macOS"
        exit 1
    }
    
    
    clear
    echo
    
    check_permissions
    check_and_kill_cursor
    backup_config
    generate_new_config
    modify_cursor_app_files
    
    # Add MAC address modification option
    echo
    log_warn "Do you want to modify MAC address?"
    echo "0) No - Keep default settings (Default)"
    echo "1) Yes - Modify MAC address"
    echo -n "Please enter selection [0-1] (Default 0): "
    read -r choice
    
    # Handle user input (including empty and invalid input)
    case "$choice" in
        1)
            if modify_mac_address; then
                log_info "MAC address modification complete!"
            else
                log_error "MAC address modification failed"
            fi
            ;;
        *)
            log_info "Skipped MAC address modification"
            ;;
    esac
    
    show_file_tree
  
    # Directly execute auto-update disable
    disable_auto_update

    log_info "Please restart Cursor to apply new configuration"

    # New restore feature option
    #restore_feature

    
}

# Execute main function
main