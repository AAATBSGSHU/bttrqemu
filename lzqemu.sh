#!/bin/bash

# directories which the software will use, uses XDG standard dirs by default
VM_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/lzqemu/vms"
ISO_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/lzqemu/isos"
LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/lzqemu/logs"

mkdir -p "$VM_DIR" "$ISO_DIR" "$LOG_DIR"

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

clear_screen() {
    clear
}

print_header() {
    echo -e "${BLUE}┌─────────────────────────────┐"
    echo -e "│         lzqemu              │"
    echo -e "└─────────────────────────────┘${NC}"
    echo
}

print_menu() {
    echo -e "${YELLOW}Available options:${NC}"
    echo -e "  ${GREEN}1${NC}) Create new VM"
    echo -e "  ${GREEN}2${NC}) Edit existing VM"
    echo -e "  ${GREEN}3${NC}) Start VM"
    echo -e "  ${GREEN}4${NC}) Stop VM"
    echo -e "  ${GREEN}5${NC}) List VMs"
    echo -e "  ${GREEN}6${NC}) Delete VM"
    echo -e "  ${GREEN}7${NC}) Exit"
    echo
    echo -n "Enter your choice [1-7]: "
}

create_vm() {
    clear_screen
    print_header
    echo -e "${YELLOW}Creating a new VM${NC}"
    echo "─────────────────────"
    read -p "VM name: " name
    read -p "Memory size (MB): " memory
    read -p "Disk size (GB): " disk_size
    read -p "ISO file name (optional): " iso

    qemu-img create -f qcow2 "$VM_DIR/${name}.qcow2" "${disk_size}G"
    cat > "$VM_DIR/${name}.conf" << EOF
name=$name
memory=$memory
disk=$VM_DIR/${name}.qcow2
iso=$ISO_DIR/$iso
EOF

    echo -e "\n${GREEN}VM '$name' created successfully.${NC}"
}

edit_vm() {
    clear_screen
    print_header
    echo -e "${YELLOW}Editing an existing VM${NC}"
    echo "─────────────────────────"
    list_vms
    echo
    read -p "Enter VM name to edit: " selected_vm

    if [ -f "$VM_DIR/${selected_vm}.conf" ]; then
        conf_file="$VM_DIR/${selected_vm}.conf"
        current_memory=$(grep "^memory=" "$conf_file" | cut -d= -f2)
        current_iso=$(grep "^iso=" "$conf_file" | cut -d= -f2)

        read -p "New memory size (MB) [${current_memory}]: " memory
        memory=${memory:-$current_memory}
        read -p "New ISO file name [${current_iso##*/}]: " iso
        iso=${iso:-${current_iso##*/}}

        sed -i "s/^memory=.*/memory=$memory/" "$conf_file"
        sed -i "s|^iso=.*|iso=$ISO_DIR/$iso|" "$conf_file"

        echo -e "\n${GREEN}VM '$selected_vm' updated successfully.${NC}"
    else
        echo -e "\n${YELLOW}VM '$selected_vm' not found.${NC}"
    fi
}

start_vm() {
    clear_screen
    print_header
    echo -e "${YELLOW}Starting a VM${NC}"
    echo "─────────────────"
    list_vms
    echo
    read -p "Enter VM name to start: " selected_vm

    if [ -f "$VM_DIR/${selected_vm}.conf" ]; then
        source "$VM_DIR/${selected_vm}.conf"

        log_file="$LOG_DIR/${name}.log"
        if [ -n "$iso" ] && [ -f "$iso" ]; then
            cmd="qemu-system-x86_64 -name \"$name\" -m \"$memory\" -boot d -hda \"$disk\" -cdrom \"$iso\" -enable-kvm"
        else
            cmd="qemu-system-x86_64 -name \"$name\" -m \"$memory\" -boot c -hda \"$disk\" -enable-kvm"
        fi

        nohup bash -c "$cmd" > "$log_file" 2>&1 &

        echo -e "\n${GREEN}VM '$selected_vm' started in the background.${NC}"
        echo -e "Logs are being written to: $log_file"
    else
        echo -e "\n${YELLOW}VM '$selected_vm' not found.${NC}"
    fi
}

stop_vm() {
    clear_screen
    print_header
    echo -e "${YELLOW}Stopping a VM${NC}"
    echo "────────────────"
    running_vms=$(pgrep -f "qemu.*-name" | wc -l)
    if [ "$running_vms" -eq 0 ]; then
        echo -e "${YELLOW}No VMs are currently running.${NC}"
        return
    fi

    echo "Running VMs:"
    pgrep -a -f "qemu.*-name" | grep -oP '(?<=-name )[^ ]+' | sed 's/^/  /'
    echo

    read -p "Enter VM name to stop: " selected_vm

    if pgrep -f "qemu.*-name $selected_vm" > /dev/null; then
        pkill -f "qemu.*-name $selected_vm"
        echo -e "\n${GREEN}VM '$selected_vm' stopped.${NC}"
    else
        echo -e "\n${YELLOW}VM '$selected_vm' is not running.${NC}"
    fi
}

delete_vm() {
    clear_screen
    print_header
    echo -e "${YELLOW}Deleting a VM${NC}"
    echo "────────────────"
    list_vms
    echo
    read -p "Enter VM name to delete: " selected_vm

    if [ -f "$VM_DIR/${selected_vm}.conf" ]; then
        rm -f "$VM_DIR/${selected_vm}.qcow2" "$VM_DIR/${selected_vm}.conf"
        echo -e "\n${GREEN}VM '$selected_vm' deleted successfully.${NC}"
    else
        echo -e "\n${YELLOW}VM '$selected_vm' not found.${NC}"
    fi
}

list_vms() {
    echo -e "${YELLOW}Available VMs:${NC}"
    if [ -n "$(ls -A "$VM_DIR"/*.conf 2>/dev/null)" ]; then
        for conf in "$VM_DIR"/*.conf; do
            vm_name=$(basename "$conf" .conf)
            echo "  $vm_name"
        done
    else
        echo "  No VMs found"
    fi
}

#               _-^-_
#               | | |
#               —————

main_menu() {
    while true; do
        clear_screen
        print_header
        print_menu

        read choice
        case $choice in
            1) create_vm ;;
            2) edit_vm ;;
            3) start_vm ;;
            4) stop_vm ;;
            5) clear_screen; print_header; list_vms ;;
            6) delete_vm ;;
            7) clear_screen; echo -e "${YELLOW}Thank you for using lzqemu VM Manager. Goodbye!${NC}"; exit 0 ;;
            *) echo -e "\n${YELLOW}Invalid option. Please try again.${NC}" ;;
        esac

        echo
        read -p "Press Enter to continue..."
    done
}

main_menu

# feedback appreciated
