<#
.SYNOPSIS
    Inventories a Windows PC in enough detail to order a compatible replacement
    or upgrade part (RAM, SSD, GPU, NIC) without opening the case.

.DESCRIPTION
    Pulls hardware facts from CIM/WMI and the Storage module. The goal is not a
    pretty spec sheet - it is the exact set of fields a parts vendor or a
    compatibility checker asks for:

      * OEM model + serial (service tag) -> look up the factory config
      * Motherboard + chassis type       -> DIMM vs SODIMM, slot count
      * Per-DIMM part numbers + speed    -> buy matching modules
      * Max RAM capacity + free slots    -> know your upgrade ceiling
      * Disk bus type + form factor      -> NVMe vs SATA, M.2 vs 2.5"
      * Free PCIe slots                  -> room for a GPU or NIC

.PARAMETER Json
    Emit machine-readable JSON instead of the formatted report. Use this when
    you want to paste the output into a chat or feed it to another tool.

.PARAMETER OutFile
    Also write the output to this path.

.EXAMPLE
    .\Get-PCSpecs.ps1
    Formatted report in the console.

.EXAMPLE
    .\Get-PCSpecs.ps1 -Json -OutFile "$env:USERPROFILE\Desktop\specs.json"
    JSON on screen and saved to the desktop.

.NOTES
    Run as Administrator for complete results. Without elevation, serial numbers
    on some OEM systems come back blank and Get-PhysicalDisk may omit fields.
    Requires PowerShell 5.1+ (ships with Windows 10/11). No modules to install.
#>
[CmdletBinding()]
param(
    [switch]$Json,
    [string]$OutFile
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# SMBIOS lookup tables. These integers come straight from the DMTF SMBIOS spec,
# which is what WMI is reading under the hood.
# ---------------------------------------------------------------------------

$MemoryTypeMap = @{
    0  = 'Unknown'; 2 = 'DRAM';   20 = 'DDR';  21 = 'DDR2'
    22 = 'DDR2 FB-DIMM';          24 = 'DDR3'; 26 = 'DDR4'
    27 = 'LPDDR';  28 = 'LPDDR2'; 29 = 'LPDDR3'; 30 = 'LPDDR4'
    34 = 'DDR5';   35 = 'LPDDR5'
}

$FormFactorMap = @{
    0 = 'Unknown'; 7 = 'SIMM'; 8 = 'DIMM'; 9 = 'TSOP'
    11 = 'RIMM';  12 = 'SODIMM'; 13 = 'SRIMM'
}

$ChassisMap = @{
    3 = 'Desktop'; 4 = 'Low Profile Desktop'; 6 = 'Mini Tower'; 7 = 'Tower'
    8 = 'Portable'; 9 = 'Laptop'; 10 = 'Notebook'; 11 = 'Hand Held'
    13 = 'All in One'; 14 = 'Sub Notebook'; 15 = 'Space-Saving'
    17 = 'Main System Chassis'; 23 = 'Rack Mount'; 30 = 'Tablet'
    31 = 'Convertible'; 32 = 'Detachable'; 35 = 'Mini PC'
}

$SlotUsageMap = @{ 1 = 'Other'; 2 = 'Unknown'; 3 = 'Available'; 4 = 'In Use' }

function ConvertTo-GB {
    param($Bytes)
    if (-not $Bytes) { return $null }
    [math]::Round([double]$Bytes / 1GB, 2)
}

function Get-CimSafe {
    # WMI classes vary by OEM and Windows edition. A missing class should
    # degrade one section, not kill the whole run.
    param([string]$ClassName)
    try { Get-CimInstance -ClassName $ClassName -ErrorAction Stop }
    catch { Write-Verbose "Could not query $ClassName : $($_.Exception.Message)"; @() }
}

# ---------------------------------------------------------------------------
# Collection
# ---------------------------------------------------------------------------

Write-Verbose 'Collecting system identity...'

$cs       = Get-CimSafe Win32_ComputerSystem     | Select-Object -First 1
$bios     = Get-CimSafe Win32_BIOS               | Select-Object -First 1
$board    = Get-CimSafe Win32_BaseBoard          | Select-Object -First 1
$enclosure= Get-CimSafe Win32_SystemEnclosure    | Select-Object -First 1
$os       = Get-CimSafe Win32_OperatingSystem    | Select-Object -First 1
$csProduct= Get-CimSafe Win32_ComputerSystemProduct | Select-Object -First 1

$chassisType = if ($enclosure.ChassisTypes) {
    $code = @($enclosure.ChassisTypes)[0]
    if ($ChassisMap.ContainsKey([int]$code)) { $ChassisMap[[int]$code] } else { "Type $code" }
} else { 'Unknown' }

$system = [ordered]@{
    Manufacturer  = $cs.Manufacturer
    Model         = $cs.Model
    SystemSKU     = $csProduct.Name
    # On Dell this is the Service Tag; on HP/Lenovo it is the serial. It is the
    # single most useful string here - it pulls the exact factory config from
    # the vendor's support site.
    SerialNumber  = $bios.SerialNumber
    UUID          = $csProduct.UUID
    ChassisType   = $chassisType
    BIOSVersion   = $bios.SMBIOSBIOSVersion
    BIOSReleased  = if ($bios.ReleaseDate) { $bios.ReleaseDate.ToString('yyyy-MM-dd') } else { $null }
    TotalRAM_GB   = ConvertTo-GB $cs.TotalPhysicalMemory
}

$motherboard = [ordered]@{
    Manufacturer = $board.Manufacturer
    Product      = $board.Product
    Version      = $board.Version
    SerialNumber = $board.SerialNumber
}

Write-Verbose 'Collecting CPU...'

$processors = @(Get-CimSafe Win32_Processor | ForEach-Object {
    [ordered]@{
        Name                = $_.Name -replace '\s+', ' '
        # SocketDesignation is what you need to confirm CPU upgrade options
        # (LGA1700, AM4, etc). OEMs sometimes report a generic label here.
        Socket              = $_.SocketDesignation
        Cores               = $_.NumberOfCores
        LogicalProcessors   = $_.NumberOfLogicalProcessors
        MaxClockMHz         = $_.MaxClockSpeed
        L3CacheKB           = $_.L3CacheSize
    }
})

Write-Verbose 'Collecting memory...'

$memArray = Get-CimSafe Win32_PhysicalMemoryArray | Select-Object -First 1

# MaxCapacityEx is UInt64 KB and is the reliable field on modern systems.
# MaxCapacity is UInt32 KB and saturates around 4 TB, so only fall back to it.
$maxCapacityGB = if ($memArray.MaxCapacityEx -and $memArray.MaxCapacityEx -gt 0) {
    [math]::Round($memArray.MaxCapacityEx / 1MB, 0)
} elseif ($memArray.MaxCapacity) {
    [math]::Round($memArray.MaxCapacity / 1MB, 0)
} else { $null }

$dimms = @(Get-CimSafe Win32_PhysicalMemory | ForEach-Object {
    $typeCode = if ($_.SMBIOSMemoryType) { [int]$_.SMBIOSMemoryType } else { 0 }
    [ordered]@{
        Slot              = $_.DeviceLocator
        Bank              = $_.BankLabel
        Capacity_GB       = ConvertTo-GB $_.Capacity
        Type              = if ($MemoryTypeMap.ContainsKey($typeCode)) { $MemoryTypeMap[$typeCode] } else { "Code $typeCode" }
        FormFactor        = if ($FormFactorMap.ContainsKey([int]$_.FormFactor)) { $FormFactorMap[[int]$_.FormFactor] } else { "Code $($_.FormFactor)" }
        RatedSpeed_MHz    = $_.Speed             # what the module is rated for
        RunningSpeed_MHz  = $_.ConfiguredClockSpeed  # what it is actually running at
        Manufacturer      = $_.Manufacturer
        PartNumber        = if ($_.PartNumber) { $_.PartNumber.Trim() } else { $null }
        SerialNumber      = if ($_.SerialNumber) { $_.SerialNumber.Trim() } else { $null }
    }
})

$totalSlots = if ($memArray.MemoryDevices) { [int]$memArray.MemoryDevices } else { $null }
$memory = [ordered]@{
    MaxCapacity_GB   = $maxCapacityGB
    TotalSlots       = $totalSlots
    PopulatedSlots   = $dimms.Count
    FreeSlots        = if ($null -ne $totalSlots) { $totalSlots - $dimms.Count } else { $null }
    InstalledTotal_GB= ConvertTo-GB $cs.TotalPhysicalMemory
    Modules          = $dimms
}

Write-Verbose 'Collecting storage...'

$disks = @()
try {
    $disks = @(Get-PhysicalDisk -ErrorAction Stop | ForEach-Object {
        [ordered]@{
            FriendlyName = $_.FriendlyName
            SerialNumber = $_.SerialNumber
            # BusType tells you NVMe vs SATA vs USB - the single field that
            # decides which drive you can actually plug in.
            BusType      = $_.BusType
            MediaType    = $_.MediaType
            Size_GB      = ConvertTo-GB $_.Size
            HealthStatus = $_.HealthStatus
            SpindleSpeed = $_.SpindleSpeed
        }
    })
} catch {
    Write-Verbose "Get-PhysicalDisk unavailable, falling back to Win32_DiskDrive"
    $disks = @(Get-CimSafe Win32_DiskDrive | ForEach-Object {
        [ordered]@{
            FriendlyName = $_.Model
            SerialNumber = if ($_.SerialNumber) { $_.SerialNumber.Trim() } else { $null }
            BusType      = $_.InterfaceType
            MediaType    = $_.MediaType
            Size_GB      = ConvertTo-GB $_.Size
            HealthStatus = $_.Status
            SpindleSpeed = $null
        }
    })
}

Write-Verbose 'Collecting graphics...'

$gpus = @(Get-CimSafe Win32_VideoController | ForEach-Object {
    $ctrl = $_
    # Win32_VideoController.AdapterRAM is a UInt32 and silently caps at 4 GB.
    # The registry value is a 64-bit int and reports the real amount.
    $vram = ConvertTo-GB $ctrl.AdapterRAM
    try {
        $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\*'
        $match = Get-ItemProperty -Path $regPath -ErrorAction Stop |
                 Where-Object { $_.DriverDesc -eq $ctrl.Name -and $_.'HardwareInformation.qwMemorySize' } |
                 Select-Object -First 1
        if ($match) { $vram = ConvertTo-GB $match.'HardwareInformation.qwMemorySize' }
    } catch { }

    [ordered]@{
        Name              = $ctrl.Name
        VRAM_GB           = $vram
        DriverVersion     = $ctrl.DriverVersion
        CurrentResolution = if ($ctrl.CurrentHorizontalResolution) {
            "$($ctrl.CurrentHorizontalResolution)x$($ctrl.CurrentVerticalResolution)"
        } else { $null }
    }
})

Write-Verbose 'Collecting expansion slots...'

$slots = @(Get-CimSafe Win32_SystemSlot | ForEach-Object {
    $usage = [int]$_.CurrentUsage
    [ordered]@{
        Designation = $_.SlotDesignation
        Usage       = if ($SlotUsageMap.ContainsKey($usage)) { $SlotUsageMap[$usage] } else { "Code $usage" }
        Shared      = $_.Shared
    }
})

Write-Verbose 'Collecting network adapters...'

$nics = @()
try {
    $nics = @(Get-NetAdapter -ErrorAction Stop | ForEach-Object {
        [ordered]@{
            Name          = $_.Name
            Description   = $_.InterfaceDescription
            MacAddress    = $_.MacAddress
            LinkSpeed     = $_.LinkSpeed
            Status        = $_.Status
        }
    })
} catch {
    $nics = @(Get-CimSafe Win32_NetworkAdapter | Where-Object { $_.PhysicalAdapter } | ForEach-Object {
        [ordered]@{
            Name        = $_.NetConnectionID
            Description = $_.Name
            MacAddress  = $_.MACAddress
            LinkSpeed   = if ($_.Speed) { "$([math]::Round($_.Speed/1e6,0)) Mbps" } else { $null }
            Status      = $_.NetConnectionStatus
        }
    })
}

$osInfo = [ordered]@{
    Caption      = $os.Caption
    Version      = $os.Version
    BuildNumber  = $os.BuildNumber
    Architecture = $os.OSArchitecture
    InstallDate  = if ($os.InstallDate) { $os.InstallDate.ToString('yyyy-MM-dd') } else { $null }
}

$report = [ordered]@{
    CollectedAt = (Get-Date).ToString('s')
    Hostname    = $env:COMPUTERNAME
    System      = $system
    Motherboard = $motherboard
    Processors  = $processors
    Memory      = $memory
    Storage     = $disks
    Graphics    = $gpus
    ExpansionSlots = $slots
    NetworkAdapters = $nics
    OperatingSystem = $osInfo
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

if ($Json) {
    $output = $report | ConvertTo-Json -Depth 6
} else {
    $sb = [System.Text.StringBuilder]::new()
    function Add-Line { param($Text = '') [void]$sb.AppendLine($Text) }
    function Add-Header {
        param($Text)
        Add-Line
        Add-Line ('=' * 72)
        Add-Line "  $Text"
        Add-Line ('=' * 72)
    }

    Add-Line "PC hardware inventory - $($env:COMPUTERNAME) - $((Get-Date).ToString('yyyy-MM-dd HH:mm'))"

    Add-Header 'SYSTEM'
    foreach ($k in $system.Keys) { Add-Line ("  {0,-16} {1}" -f $k, $system[$k]) }
    Add-Line ("  {0,-16} {1}" -f 'OS', "$($osInfo.Caption) $($osInfo.Architecture) (build $($osInfo.BuildNumber))")

    Add-Header 'MOTHERBOARD'
    foreach ($k in $motherboard.Keys) { Add-Line ("  {0,-16} {1}" -f $k, $motherboard[$k]) }

    Add-Header 'PROCESSOR'
    foreach ($p in $processors) {
        Add-Line ("  {0,-16} {1}" -f 'Name', $p.Name)
        Add-Line ("  {0,-16} {1}" -f 'Socket', $p.Socket)
        Add-Line ("  {0,-16} {1} cores / {2} threads @ {3} MHz" -f 'Topology', $p.Cores, $p.LogicalProcessors, $p.MaxClockMHz)
    }

    Add-Header 'MEMORY  (what to buy)'
    Add-Line ("  {0,-16} {1} GB" -f 'Installed', $memory.InstalledTotal_GB)
    Add-Line ("  {0,-16} {1} GB" -f 'Max supported', $memory.MaxCapacity_GB)
    Add-Line ("  {0,-16} {1} total, {2} populated, {3} free" -f 'Slots', $memory.TotalSlots, $memory.PopulatedSlots, $memory.FreeSlots)
    Add-Line
    foreach ($d in $dimms) {
        Add-Line "  [$($d.Slot)]"
        Add-Line ("      {0,-14} {1} GB {2} {3}" -f 'Module', $d.Capacity_GB, $d.Type, $d.FormFactor)
        Add-Line ("      {0,-14} {1} MHz rated / {2} MHz running" -f 'Speed', $d.RatedSpeed_MHz, $d.RunningSpeed_MHz)
        Add-Line ("      {0,-14} {1}" -f 'Manufacturer', $d.Manufacturer)
        Add-Line ("      {0,-14} {1}" -f 'Part number', $d.PartNumber)
    }

    Add-Header 'STORAGE'
    foreach ($d in $disks) {
        Add-Line ("  {0}" -f $d.FriendlyName)
        Add-Line ("      {0,-14} {1} GB, {2}, bus {3}, health {4}" -f 'Detail', $d.Size_GB, $d.MediaType, $d.BusType, $d.HealthStatus)
    }

    Add-Header 'GRAPHICS'
    foreach ($g in $gpus) {
        Add-Line ("  {0}" -f $g.Name)
        Add-Line ("      {0,-14} {1} GB, driver {2}, {3}" -f 'Detail', $g.VRAM_GB, $g.DriverVersion, $g.CurrentResolution)
    }

    Add-Header 'EXPANSION SLOTS'
    if ($slots.Count -eq 0) {
        Add-Line '  (none reported - common on laptops and some OEM desktops)'
    } else {
        foreach ($s in $slots) { Add-Line ("  {0,-34} {1}" -f $s.Designation, $s.Usage) }
    }

    Add-Header 'NETWORK ADAPTERS'
    foreach ($n in $nics) {
        Add-Line ("  {0,-22} {1}" -f $n.Name, $n.Description)
        Add-Line ("      {0,-14} {1}  link {2}  [{3}]" -f 'MAC', $n.MacAddress, $n.LinkSpeed, $n.Status)
    }

    Add-Line
    Add-Line ('-' * 72)
    Add-Line 'NOT detectable in software - you have to look or check the OEM spec sheet:'
    Add-Line '  * Power supply wattage and connectors (matters for a GPU upgrade)'
    Add-Line '  * Physical M.2 slot length (2242 / 2260 / 2280) and free M.2 slots'
    Add-Line '  * Case clearance for a cooler or full-length card'
    Add-Line "  * Fastest path: search the serial above on the OEM support site"
    Add-Line ('-' * 72)

    $output = $sb.ToString()
}

if ($OutFile) {
    $output | Out-File -FilePath $OutFile -Encoding utf8
    Write-Host "Saved to $OutFile" -ForegroundColor Green
}

$output
