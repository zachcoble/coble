# Ordering a part without opening the case

The script gives you the raw fields. This is how to turn them into a correct
order. This is the workflow you'd use at a help desk when someone drops a
machine on your bench and asks "can we put more RAM in this."

## Step 1: the serial is the shortcut

`Get-PCSpecs.ps1` prints `SerialNumber` under **SYSTEM**. On Dell that's the
Service Tag; on HP and Lenovo it's the serial.

| Vendor | Where to look it up |
|---|---|
| Dell | dell.com/support -> enter Service Tag |
| HP | support.hp.com -> enter serial |
| Lenovo | pcsupport.lenovo.com -> enter serial |

That page gives you the **factory configuration** - the exact parts that
shipped in that chassis, plus the service manual with teardown steps and the
qualified-parts list. For an OEM prebuilt this beats any amount of WMI
querying, because it tells you what the vendor will *support*, not just what
physically fits.

For a whitebox / self-built machine there's no such lookup. Use the
motherboard `Product` field instead and go to the board manufacturer's QVL
(Qualified Vendor List).

## Step 2: reading the memory section

```
MEMORY  (what to buy)
  Installed        16 GB
  Max supported    64 GB
  Slots            4 total, 2 populated, 2 free

  [DIMM_A1]
      Module         8 GB DDR4 DIMM
      Speed          3200 MHz rated / 2933 MHz running
      Manufacturer   Samsung
      Part number    M378A1K43EB2-CWE
```

What each line decides:

- **Max supported / free slots** - your ceiling. If it says 2 free, you can add
  without throwing anything away. If 0 free, an upgrade means replacing sticks.
- **DDR4 vs DDR5** - not interchangeable. Different notch position, different
  slot. Getting this wrong is the most common ordering mistake.
- **DIMM vs SODIMM** - desktop vs laptop form factor. Also not interchangeable.
  Cross-check against `ChassisType` in the SYSTEM section.
- **Rated vs running speed** - if rated is 3200 but running is 2933, the CPU or
  board is clocking it down. Buy to match the *rated* speed of what's already
  in there; mixing speeds makes every stick run at the slowest one.
- **Part number** - the precise thing to search. Buying an identical part
  number is the safest possible upgrade.

### Dual channel

Memory controllers run in channels. Two matched sticks in the correct slots are
meaningfully faster than one stick of twice the size, because the controller
can interleave across both.

The `Slot` labels tell you the pairing. `DIMM_A1 / DIMM_B1` is one channel pair;
`DIMM_A2 / DIMM_B2` is the other. Populate matched pairs. The motherboard manual
(from the service page in step 1) has the exact fill order - it is usually
*not* "left to right."

### Mixed sticks

You *can* mix capacities and brands. The system will boot. But everything drops
to the slowest stick's timings, and some boards get flaky about it. If you're
buying anyway, buy a matched kit.

## Step 3: storage

```
STORAGE
  Samsung SSD 980 PRO 1TB
      Detail         931.51 GB, SSD, bus NVMe, health Healthy
```

- **BusType `NVMe`** - M.2 slot, PCIe lanes. Fast.
- **BusType `SATA`** - either a 2.5" drive or an M.2 SATA stick. Confusing,
  because M.2 is a *connector*, not a protocol. An M.2 slot may be wired for
  NVMe, SATA, or both. The service manual says which.
- **`MediaType`** - `HDD` means spinning. Replacing a spinning disk with an SSD
  is still the single biggest perceived speed upgrade you can do for a user.
- **`HealthStatus`** - anything other than `Healthy` means back it up now, not
  after lunch.

**The script cannot tell you M.2 physical length** (2280 is standard, 2242 and
2260 exist in small laptops) or how many M.2 slots are free. That's a service
manual or eyeball question.

## Step 4: what software can never tell you

Print this on the inside of your skull:

- **PSU wattage and connectors.** Nothing in WMI reports this. Matters
  enormously for a GPU upgrade. Open the case and read the label.
- **Physical clearance.** Cooler height, GPU length, case fan size.
- **Free M.2 slots and their keying.**
- **Whether the warranty is still active** - check with the serial before you
  open anything.

## Quick reference: what to run

```powershell
# Readable report
.\scripts\Get-PCSpecs.ps1

# JSON to paste into a chat or feed to a tool
.\scripts\Get-PCSpecs.ps1 -Json

# Save it for a ticket
.\scripts\Get-PCSpecs.ps1 -OutFile "$env:USERPROFILE\Desktop\specs.txt"
```

Run elevated. Some OEMs hide serial numbers from non-admin WMI queries.

## Why this is worth having as a script

Running this across a fleet and keeping the JSON is the beginning of a real
asset inventory - warranty status, RAM headroom, disks nearing end of life.
That's the jump from "I fix tickets" to "I know what's on the network," which
is the same jump that shows up on a resume as asset management or capacity
planning. It's also three lines away from being a Group Policy startup script
that writes JSON to a share.
