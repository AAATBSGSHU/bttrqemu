#!/bin/bash

# directories which the software will use, uses XDG standard dirs by default
VM_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/lzqemu/vms"
ISO_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/lzqemu/isos"
LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/lzqemu/logs"

mkdir -p "$VM_DIR" "$ISO_DIR" "$LOG_DIR"

# Color definitions
declare -A colors=(
    [GREEN]="\033[0;32m"
    [YELLOW]="\033[1;33m"
    [BLUE]="\033[1;34m"
    [RED]="\033[0;31m"
    [CYAN]="\033[0;36m"
    [BOLD]="\033[1m"
    [RESET]="\033[0m"
)

clear_screen() {
    clear
}

print_header() {
    local header_text="$1"
    echo -e "${colors[BLUE]}${colors[BOLD]}$header_text${colors[RESET]}"
    echo -e "${colors[CYAN]}-------------------------------------------${colors[RESET]}"
}

print_menu() {
    local selected_index="$1"
    local options=(
        "Create new VM"
        "Edit existing VM"
        "Start VM"
        "Stop VM"
        "List VMs"
        "Delete VM"
        "Exit"
    )

    echo -e "${colors[YELLOW]}Use Up/Down arrows to select options. Press Enter to choose. Press Left arrow to go back.${colors[RESET]}"
    echo

    for i in "${!options[@]}"; do
        if [ $i -eq $selected_index ]; then
            echo -e "${colors[GREEN]}> ${options[$i]}${colors[RESET]}"
        else
            echo "  ${options[$i]}"
        fi
    done
}

read_with_escape() {
    local prompt="$1"
    local input=""
    local key

    echo -n "$prompt"
    while IFS= read -r -n1 -s key; do
        if [[ $key == $'\x1b' ]]; then
            read -r -n2 -s rest
            key+="$rest"
            if [[ $key == $'\x1b[D' ]]; then
                echo
                return 1
            fi
        elif [[ $key == $'\n' ]]; then
            echo
            break
        else
            echo -n "$key"
            input+="$key"
        fi
    done

    echo "$input"
    return 0
}

create_vm() {
    while true; do
        clear_screen
        print_header "Creating a new VM"

        read_with_escape "VM name: " && name=$? || return
        read_with_escape "Memory size (MB): " && memory=$? || return
        read_with_escape "Disk size (GB): " && disk_size=$? || return
        read_with_escape "ISO file name (optional): " && iso=$? || return

        qemu-img create -f qcow2 "$VM_DIR/${name}.qcow2" "${disk_size}G"
        cat > "$VM_DIR/${name}.conf" << EOF
name=$name
memory=$memory
disk=$VM_DIR/${name}.qcow2
iso=$ISO_DIR/$iso
EOF

        echo -e "\n${colors[GREEN]}VM '$name' created successfully.${colors[RESET]}"
        read -p "Press Enter to continue..."
        return
    done
}

edit_vm() {
    while true; do
        clear_screen
        print_header "Editing an existing VM"
        list_vms
        echo

        read_with_escape "Enter VM name to edit: " && selected_vm=$? || return

        if [ -f "$VM_DIR/${selected_vm}.conf" ]; then
            conf_file="$VM_DIR/${selected_vm}.conf"
            current_memory=$(grep "^memory=" "$conf_file" | cut -d= -f2)
            current_iso=$(grep "^iso=" "$conf_file" | cut -d= -f2)

            read_with_escape "New memory size (MB) [${current_memory}]: " && memory=$? || return
            memory=${memory:-$current_memory}
            read_with_escape "New ISO file name [${current_iso##*/}]: " && iso=$? || return
            iso=${iso:-${current_iso##*/}}

            sed -i "s/^memory=.*/memory=$memory/" "$conf_file"
            sed -i "s|^iso=.*|iso=$ISO_DIR/$iso|" "$conf_file"

            echo -e "\n${colors[GREEN]}VM '$selected_vm' updated successfully.${colors[RESET]}"
        else
            echo -e "\n${colors[RED]}VM '$selected_vm' not found.${colors[RESET]}"
        fi

        read -p "Press Enter to continue..."
        return
    done
}

start_vm() {
    while true; do
        clear_screen
        print_header "Starting a VM"
        list_vms
        echo

        read_with_escape "Enter VM name to start: " && selected_vm=$? || return

        if [ -f "$VM_DIR/${selected_vm}.conf" ]; then
            source "$VM_DIR/${selected_vm}.conf"

            log_file="$LOG_DIR/${name}.log"
            if [ -n "$iso" ] && [ -f "$iso" ]; then
                cmd="qemu-system-x86_64 -name \"$name\" -m \"$memory\" -boot d -hda \"$disk\" -cdrom \"$iso\" -enable-kvm"
            else
                cmd="qemu-system-x86_64 -name \"$name\" -m \"$memory\" -boot c -hda \"$disk\" -enable-kvm"
            fi

            nohup bash -c "$cmd" > "$log_file" 2>&1 &

            echo -e "\n${colors[GREEN]}VM '$selected_vm' started in the background.${colors[RESET]}"
            echo -e "Logs are being written to: $log_file"
        else
            echo -e "\n${colors[RED]}VM '$selected_vm' not found.${colors[RESET]}"
        fi

        read -p "Press Enter to continue..."
        return
    done
}

stop_vm() {
    while true; do
        clear_screen
        print_header "Stopping a VM"
        running_vms=$(pgrep -f "qemu.*-name" | wc -l)
        if [ "$running_vms" -eq 0 ]; then
            echo -e "${colors[RED]}No VMs are currently running.${colors[RESET]}"
            read -p "Press Enter to continue..."
            return
        fi

        echo "Running VMs:"
        pgrep -a -f "qemu.*-name" | grep -oP '(?<=-name )[^ ]+' | sed 's/^/  /'
        echo

        read_with_escape "Enter VM name to stop: " && selected_vm=$? || return

        if pgrep -f "qemu.*-name $selected_vm" > /dev/null; then
            pkill -f "qemu.*-name $selected_vm"
            echo -e "\n${colors[GREEN]}VM '$selected_vm' stopped.${colors[RESET]}"
        else
            echo -e "\n${colors[RED]}VM '$selected_vm' is not running.${colors[RESET]}"
        fi

        read -p "Press Enter to continue..."
        return
    done
}

delete_vm() {
    while true; do
        clear_screen
        print_header "Deleting a VM"
        list_vms
        echo

        read_with_escape "Enter VM name to delete: " && selected_vm=$? || return

        if [ -f "$VM_DIR/${selected_vm}.conf" ]; then
            rm -f "$VM_DIR/${selected_vm}.qcow2" "$VM_DIR/${selected_vm}.conf"
            echo -e "\n${colors[GREEN]}VM '$selected_vm' deleted successfully.${colors[RESET]}"
        else
            echo -e "\n${colors[RED]}VM '$selected_vm' not found.${colors[RESET]}"
        fi

        read -p "Press Enter to continue..."
        return
    done
}

list_vms() {
    echo -e "${colors[YELLOW]}Available VMs:${colors[RESET]}"
    if [ -n "$(ls -A "$VM_DIR"/*.conf 2>/dev/null)" ]; then
        for conf in "$VM_DIR"/*.conf; do
            vm_name=$(basename "$conf" .conf)
            echo "  $vm_name"
        done
    else
        echo "  No VMs found"
    fi
}

main_menu() {
    local selected_index=0

    while true; do
        clear_screen
        print_header "bttrqemu - A better way to use QEMU"
        print_menu "$selected_index"

        read -rsn1 key
        case "$key" in
            $'\x1b')
                read -rsn2 key
                case "$key" in
                    '[A') ((selected_index > 0)) && ((selected_index--)) ;;
                    '[B') ((selected_index < 6)) && ((selected_index++)) ;;
                esac
                ;;
            "")
                case $selected_index in
                    0) create_vm ;;
                    1) edit_vm ;;
                    2) start_vm ;;
                    3) stop_vm ;;
                    4) clear_screen; print_header "List VMs"; list_vms; read -p "Press Enter to continue..." ;;
                    5) delete_vm ;;
                    6) clear_screen; echo -e "${colors[YELLOW]}Sayonara!${colors[RESET]}"; exit 0 ;;
                esac
                ;;
        esac
    done
}

main_menu

# feedback appreciated
