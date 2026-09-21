#!/usr/bin/env bash
# Inventories a Linux machine in enough detail to order a compatible part.
# Linux counterpart to Get-PCSpecs.ps1.
#
# Run with sudo for the DMI fields (model, serial, per-DIMM part numbers).
# Without root, dmidecode is unavailable and those sections are skipped.
#
# Usage: ./get-pc-specs.sh [--json]

set -uo pipefail

JSON=0
[[ "${1:-}" == "--json" ]] && JSON=1

have() { command -v "$1" >/dev/null 2>&1; }

hdr() {
    printf '\n%s\n  %s\n%s\n' "$(printf '=%.0s' {1..72})" "$1" "$(printf '=%.0s' {1..72})"
}

# dmidecode needs root. Degrade to the sysfs DMI files, which are world-readable
# for most of the identity fields (serial numbers are root-only there too).
dmi() {
    local file="/sys/class/dmi/id/$1"
    [[ -r "$file" ]] && tr -d '\n' < "$file" || echo "unavailable"
}

if [[ $JSON -eq 1 ]]; then
    # Minimal JSON for pasting into a chat or piping to jq.
    printf '{\n'
    printf '  "hostname": "%s",\n' "$(hostname)"
    printf '  "vendor": "%s",\n' "$(dmi sys_vendor)"
    printf '  "product": "%s",\n' "$(dmi product_name)"
    printf '  "serial": "%s",\n' "$(dmi product_serial)"
    printf '  "board": "%s",\n' "$(dmi board_name)"
    printf '  "bios_version": "%s",\n' "$(dmi bios_version)"
    printf '  "cpu": "%s",\n' "$(lscpu 2>/dev/null | awk -F': +' '/Model name/{print $2; exit}')"
    printf '  "mem_total_kb": %s,\n' "$(awk '/MemTotal/{print $2}' /proc/meminfo)"
    printf '  "kernel": "%s"\n' "$(uname -r)"
    printf '}\n'
    exit 0
fi

echo "PC hardware inventory - $(hostname) - $(date '+%Y-%m-%d %H:%M')"

hdr "SYSTEM"
printf '  %-16s %s\n' "Vendor"    "$(dmi sys_vendor)"
printf '  %-16s %s\n' "Model"     "$(dmi product_name)"
printf '  %-16s %s\n' "Version"   "$(dmi product_version)"
printf '  %-16s %s\n' "Serial"    "$(dmi product_serial)"
printf '  %-16s %s\n' "Chassis"   "$(dmi chassis_type)"
printf '  %-16s %s\n' "BIOS"      "$(dmi bios_version) ($(dmi bios_date))"
printf '  %-16s %s\n' "Kernel"    "$(uname -r)"
if have systemd-detect-virt; then
    printf '  %-16s %s\n' "Virtualization" "$(systemd-detect-virt 2>/dev/null || echo none)"
fi
if [[ -r /etc/os-release ]]; then
    printf '  %-16s %s\n' "OS" "$(awk -F= '/^PRETTY_NAME/{gsub(/"/,"",$2); print $2}' /etc/os-release)"
fi

hdr "MOTHERBOARD"
printf '  %-16s %s\n' "Vendor"  "$(dmi board_vendor)"
printf '  %-16s %s\n' "Product" "$(dmi board_name)"
printf '  %-16s %s\n' "Version" "$(dmi board_version)"

hdr "PROCESSOR"
if have lscpu; then
    lscpu | grep -E '^(Model name|Socket|Core\(s\) per socket|Thread\(s\) per core|CPU\(s\)|CPU max MHz|Vendor ID)' \
          | sed 's/^/  /'
else
    grep -m1 'model name' /proc/cpuinfo | sed 's/^/  /'
fi

hdr "MEMORY  (what to buy)"
printf '  %-16s %s\n' "Installed" "$(awk '/MemTotal/{printf "%.1f GB", $2/1024/1024}' /proc/meminfo)"
if have dmidecode && [[ $EUID -eq 0 ]]; then
    echo
    # Type 16 = Physical Memory Array: the upgrade ceiling and slot count.
    dmidecode -t 16 2>/dev/null | grep -E 'Maximum Capacity|Number Of Devices' | sed 's/^\s*/  /'
    echo
    # Type 17 = Memory Device: one entry per slot, populated or not.
    dmidecode -t 17 2>/dev/null \
      | grep -E 'Locator:|Size:|Type:|Speed:|Manufacturer:|Part Number:|Form Factor:' \
      | grep -v 'Bank Locator' | sed 's/^\s*/    /'
else
    echo "  (run with sudo for per-slot detail: sudo $0)"
fi

hdr "STORAGE"
if have lsblk; then
    lsblk -d -o NAME,MODEL,SIZE,ROTA,TRAN,TYPE 2>/dev/null | sed 's/^/  /'
    echo
    echo "  ROTA=1 is a spinning disk, ROTA=0 is flash. TRAN is the bus (nvme/sata/usb)."
fi
if have nvme; then
    echo
    nvme list 2>/dev/null | sed 's/^/  /'
fi

hdr "GRAPHICS"
if have lspci; then
    lspci 2>/dev/null | grep -Ei 'vga|3d|display' | sed 's/^/  /'
else
    echo "  (lspci not installed - apt install pciutils)"
fi

hdr "EXPANSION SLOTS"
if have dmidecode && [[ $EUID -eq 0 ]]; then
    dmidecode -t 9 2>/dev/null | grep -E 'Designation:|Current Usage:|Type:' | sed 's/^\s*/  /'
else
    echo "  (run with sudo)"
fi

hdr "NETWORK ADAPTERS"
if have lspci; then
    lspci 2>/dev/null | grep -Ei 'ethernet|network' | sed 's/^/  /'
fi
if have ip; then
    echo
    for n in /sys/class/net/*; do
        i=$(basename "$n")
        [[ "$i" == "lo" ]] && continue
        speed=$(cat "$n/speed" 2>/dev/null || echo "?")
        mac=$(cat "$n/address" 2>/dev/null)
        state=$(cat "$n/operstate" 2>/dev/null)
        printf '  %-12s %-20s %s Mb/s  [%s]\n' "$i" "$mac" "$speed" "$state"
    done
fi

echo
printf -- '-%.0s' {1..72}; echo
echo "NOT detectable in software - check physically or on the OEM spec sheet:"
echo "  * Power supply wattage and connectors"
echo "  * Physical M.2 slot length (2242 / 2260 / 2280) and free M.2 slots"
echo "  * Case clearance for a cooler or full-length card"
printf -- '-%.0s' {1..72}; echo
