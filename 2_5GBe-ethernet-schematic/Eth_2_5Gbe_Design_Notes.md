# 2.5GbE Ethernet sheet: design notes

Sheet: `Eth_2_5Gbe.SchDoc` (project `USRP-sdr.PrjPcb`)
Date: 2026-11-21. Part values, nets and notes were read back from the sheet in Altium on this date.

These notes cover what is on the Ethernet sheet, how it connects to the rest of the board, what was changed in the libraries and project, and why. Items still marked **[VERIFY]** on the sheet are listed at the end.

---

## 1. What the sheet does

```
RJ45 cable ─► J501 magjack ─► U501 MxL86211C ─(serial pair, AC-coupled)─► FPGA GTP quad 216 lane 0 ─► LiteEth MAC
              (magnetics, LEDs)   2.5GBASE-T PHY        MDC / MDIO / RST_N / INT_N ─► FPGA bank 16 (3.3 V)
```

| Ref | Part | Role |
|---|---|---|
| U501 | MaxLinear MxL86211C | 2.5GBASE-T PHY: copper side to the jack, serial side (SGMII / 2500BASE-X) to the FPGA |
| J501 | Bel L836-121T-KD | RJ45 jack with built-in magnetics, cable-side 75R/1000 pF network and LEDs |
| FPGA (not on this sheet) | Xilinx XC7A100T-FGG484 | Runs the LiteEth MAC on one GTP transceiver |

These choices were fixed in the brief and not reopened: the PHY, magjack, FPGA, LiteEth and the TPS62825A 0.97 V regulator.

### Sheet conventions
- C-size sheet in **mil**, **100 mil grid**.
- Designators are in the **500 range**, so they can't clash with Sheet1–3.
- Text uses only ASCII: `200R`, `1k`, `4k7`, `1M`, `uF`. Altium turns characters above U+00FF into `?`.

---

## 2. Connections to the rest of the board

### 2.1 FPGA links (off-sheet connectors)

At your request, everything going to the FPGA uses **off-sheet connectors**. The project's **Net Identifier Scope is Flat**, which makes these join by name across sheets. "Automatic" would have treated a project without ports as Global.

The FPGA sheet has to use **exactly these names**:

| Net | Signal flow | FPGA ball | FPGA pin |
|---|---|---|---|
| ETH_PHY_TX_P | PHY serial **out** → FPGA GTP **receiver** | **B8** | MGTPRXP0_216 |
| ETH_PHY_TX_N | PHY serial out → FPGA GTP receiver | **A8** | MGTPRXN0_216 |
| ETH_PHY_RX_P | FPGA GTP **transmitter** → PHY serial **in** | **B4** | MGTPTXP0_216 |
| ETH_PHY_RX_N | FPGA GTP transmitter → PHY serial in | **A4** | MGTPTXN0_216 |
| ETH_MDC | FPGA → PHY | **A13** | IO_L10P_T1_16 |
| ETH_MDIO | both ways | **A14** | IO_L10N_T1_16 |
| ETH_PHY_INT_N | PHY → FPGA | **A18** | IO_L17P_T2_16 |
| ETH_PHY_RST_N | FPGA → PHY | **A19** | IO_L17N_T2_16 |

- Net names follow the **PHY's** view: `ETH_PHY_TX` is what the PHY transmits, so it lands on the FPGA's **RX** balls. This was checked on the sheet: U501-19/20, the PHY's serial input, go through C562/C563 to `ETH_PHY_RX_P/N`.
- All balls were checked against AMD's package file `xc7a100tfgg484pkg.txt`.
- Bank 16 is a High-Range bank, and these pins run as **LVCMOS33**, the 3.3 V the PHY's management pins use.
- The A13/A14/A18/A19 assignment is marked **provisional** on the sheet. The FPGA sheet and the XDC constraints have to use the same balls.
- The serial pairs and the four cable pairs at J501 carry **DifferentialPair** directives, so the PCB gets 100 Ω differential rules for them.

### 2.2 AC coupling: C560–C563 (0.1 uF, 16 V, 0402)
These capacitors sit in series in the four serial lines, **on this sheet** as you asked. For example: U501-19 → `PHY_RX_P_C` → C562 → `ETH_PHY_RX_P`.

**Why:** the PHY's serial interface and the GTP sit at different DC (common-mode) voltages. The series caps block the DC and pass the signal. On the PCB, put each cap near the **receiving** end of its lane.

### 2.3 FPGA reference clock (not on this sheet)
The GTP needs a reference clock on **MGTREFCLK0 (F6/E6)** or **MGTREFCLK1 (F10/E10)**. It belongs on the FPGA or clock sheet and hasn't been chosen yet.

### 2.4 Power rails

| Rail | On sheet as | Source | Feeds |
|---|---|---|---|
| `3v3` | power port | Sheet3 buck `3v3` (your choice) | PHY 3.3 V supply (VHIGH), pull-ups, LEDs |
| `0v97` | power port | **TPS62825A, not placed yet** | PHY 0.97 V core (VLOW): U501-7, -13, -26 |
| `GND` | power port | | |
| 3V3_PHY_A / _XO / _SG | sheet-local labels | `3v3` through ferrites FB501–FB503 | analog, crystal oscillator, serial supplies |
| 0V97_PHY_A / _SG | sheet-local labels | `0v97` through 0R links R530 / R531 (0603) | analog and serial core supplies |

- **FB501–FB503:** Murata BLM18PG221SN1D, 220R at 100 MHz, 1.4 A at 85 °C, 0.14 Ω max. They keep digital switching noise out of the quiet analog, oscillator and serial PLL supplies.
- **R530/R531 (0R):** placeholders on the 0.97 V branches. Each can be swapped for a ferrite if the first boards show noise there.
- **Bulk and decoupling:**
  - C530 10 uF and C557 22 uF / C558 10 uF on the rails.
  - 0.1 uF (C540–C545, C547, C550–C555) and 1 uF (C546, C548, C549, C556, C559) at the PHY supply pins.
- **Power sequencing** (sheet note, from the datasheet):
  - VHIGH (3v3) must come up before VLOW (0v97), with VLOW ramping at least 100 us later.
  - VLOW must stay within 0.94–1.00 V with at most 40 mVpp ripple.

---

## 3. Circuit blocks

### 3.1 Cable side → J501
- **MDI pairs:** the PHY's four pairs run straight to the jack. They were already wired correctly and were checked pin by pin.
- **Chip-side centre-tap caps C510–C513:** 100 nF, ±20 %, 50 V, X7R, 0402 (workspace part CMP-001-00067-3).
  - The datasheet (Rev 1.3, Table 40, p.170) lists C_CMC as 100 nF **2 kV**.
  - You chose the usual 50 V part. **Why that's acceptable:** the 2 kV isolation is on the **cable side**, inside J501. These caps sit on the chip side of the transformer.
  - The only 2 kV, 100 nF SMD part found (Knowles 2220, WS3) needs conformal coating. Revisit this if a hipot test is required.
- **Shield:** J501 pins 18/19 (SHIELD) → `ETH_SHIELD` → **R520 1M in parallel with C520 1 nF / 2 kV** (KYOCERA AVX 1206GC102KAT2A) → GND.
  - The 1M slowly drains static from the cable shield.
  - The 1 nF passes high-frequency noise to ground.
  - The 2 kV rating means the cap survives an ESD or surge hit on the shield.
  - The earlier part number, GRM31BR73D102KW01L, doesn't exist and was replaced.
- **J501 symbol:** SHIELD pins 18 and 19 were added to match the footprint's two plated shield holes. Before that, those pads had no net.
- **ESD U502/U503:** TI TPD4E05U06DQAR, placed flow-through between the PHY and J501. U502 covers pairs A/B and U503 covers pairs C/D.
  - They are **not fitted** in `Eth_Default`: the magnetics already isolate the PHY.
  - The footprints stay on the board so the parts can be fitted later if ESD testing calls for them.

### 3.2 Crystal Y501
- **ABM3-25.000MHZ-D2Y-T**: 25 MHz, CL 18 pF, ESR 30R, ±20/±30 ppm. Load caps **C501/C502 are 30 pF**.
  - Two 30 pF caps in series give 15 pF.
  - The board's stray capacitance adds about 3 pF, which reaches the 18 pF load the crystal needs.
- **Known problem:** Abracon specifies **C0 up to 7 pF**, but the MxL86211C datasheet (Rev 1.3, Table 39, p.169) requires **C0 ≤ 5 pF**.
  - Every Abracon 25 MHz, 18 pF family was checked (ABM3, 3B, 3C, 8, 10), and all list 7 pF max.
  - You chose to keep it: there's no long-cable test in the experiment.
  - Next step: ask Abracon for a C0 ≤ 5 pF guarantee, or check that the oscillator starts reliably on the first boards.

### 3.3 Bias reference
- **R501: 200R, 1 %, 0402.** This is the PHY's reference resistor, which sets the analog front end's bias currents. That's why it is a 1 % part. Place it close to its pin, with a short ground return.

### 3.4 Straps (1k resistors, per the datasheet)
Strap pins are read at reset. They are set by 1k pull-ups or pull-downs (R503, R505–R514):

| Strap | Setting |
|---|---|
| GPC1, GPC2, LED1 = 1 | PHY address **7** |
| LED0 = 1 | normal mode |
| LED2 = 0 | jack **tab down** |
| MDINT = 1 | interrupt active **low** |

R506, R507, R510, R512 and R513 are **not fitted** alternates. Moving one resistor flips its strap. The tab-direction strap (R513/R514) is to be confirmed on the first board.

### 3.5 Management, reset, interrupt
- **R502 1k5:** MDIO pull-up to 3v3 (the open-drain bus needs one).
- **R504 4k7:** pull-up on ETH_PHY_RST_N, so the PHY stays in a known state while the FPGA isn't configured.
  - Firmware still holds it low until the FPGA is up (see 3.7).
  - **TP501** gives a probe point on this net.
- ETH_PHY_INT_N is active low.
- The unused DVS pin has a No-ERC marker.

### 3.6 LEDs
**R515–R517 (330R)** are the series resistors for the jack's LEDs. What each LED shows is set in firmware:

| Register | Value | LED |
|---|---|---|
| MMD 30.1 | 0x0370 | LED0 yellow: 1G/100M/10M link + activity |
| MMD 30.2 | 0x0380 | LED1 green: 2.5G link + activity |
| MMD 30.3 | 0x00F0 | LED2 green: link at any speed |

### 3.7 Firmware bring-up (sheet note)
1. Hold HRSTN (ETH_PHY_RST_N) low until the FPGA is configured.
2. Release it, then wait **≥ 750 ms**.
3. Read-modify-write **MMD 30 reg 8**:
   - set bit 5 `SGMII_FIXED2G5`;
   - clear bit 12 `ANEN`;
   - keep bit 10 `RXINV`.
   - The register goes from 0x34DA to 0x24FA.
4. MMD registers are reached through Clause 22 registers 13/14.
5. The serial link is held at 2.5G by firmware with autonegotiation off, which matches a fixed-rate LiteEth core.

### 3.8 Test points (1.0 mm round SMD pads, `TP_SMD_1R00`)
| Ref | Net | Why |
|---|---|---|
| TP501 | ETH_PHY_RST_N | Watch the reset release; force a reset during bring-up |
| TP502 | 0v97 | Check the 0.94–1.00 V window, ripple and sequencing without probing a QFN pin |

---

## 4. Library work and why

You allowed library and project changes partway through.

### 4.1 `Eth_Local.SchLib` (new, in the project)
| Symbol | Footprint | Land pattern source |
|---|---|---|
| RES_0402 | RESC1005X40N_RC0402 | IPC-7351B (Yageo RC) |
| RES_1206 | RESC3216X65N_RC1206 | IPC-7351B (Yageo RC) |
| CAP_0402 | CAPC1005X55N_GRM155 | IPC-7351B (Murata GRM155) |
| CAP_1206HV | CAPC3316X180N_AVX1206HV | IPC-7351B (KYOCERA AVX HV) |
| FERRITE | MURATA_BLM18P_0603 | Murata's reflow land (spec JENF243A p.9) |
| XTAL2P | ABRACON_ABM3_5.0x3.2 | Abracon's land (ABM3 p.3) |
| TPD4E05U06DQAR | TI_USON-10_DQA0010A | TI land pattern A (SLVSBO7O p.29) |
| TESTPOINT | TP_SMD_1R00 | 1.0 mm round SMD pad |

**Why vendor land patterns were used where they exist:** they match the maker's reflow tests. Where the maker gives none, IPC-7351B nominal is used.

### 4.2 `Eth_Local.PcbLib` (new, in the project)
Holds all the footprints above, plus **MXL_VQFN-40_5x5_P0.4_EP3.79** for U501. MaxLinear gives no land pattern, so it was calculated to IPC-7351B from the package drawing (Fig. 23, p.174).

### 4.3 Existing libraries changed
- **`Ethernet_PHY.SchLib` (MxL86211C):** pins moved onto the 100 mil grid so wires meet pin ends. Designator set to `U?`. Linked to the new VQFN footprint, with all 41 pins matched to pads.
- **`L836-121T-KD.SchLib` (magjack):** SHIELD pins 18 and 19 added (see 3.1).

### 4.4 Workspace (managed) parts
**42 general resistors and capacitors** come from your Altium 365 workspace (CMP-001-…, CMP-009-…). They carry real manufacturer part numbers and supply data for the BOM. Parts with no workspace match, or that need a particular footprint, stay in `Eth_Local.SchLib`:
- C501/C502, C520
- R501, R502, R520
- FB501–FB503
- Y501
- U502/U503
- TP501/TP502

### 4.5 Checks switched off during the build
- **"Symbol vs pin table"** was off for TPD4E05U06DQAR: TI's pin table uses an en dash, which was written as `-`.
- **"Footprint vs drawing"** was off for TI_USON-10: TI's 0.05 mm land corner radius was approximated with rounded rectangles.

Both parts carry an `unchecked` flag. **Switch "Footprint vs drawing" back on.**

---

## 5. Project-level changes
- **Net Identifier Scope → Flat.**
- **Variant `Eth_Default`:** R506, R507, R510, R512, R513, U502 and U503 are Not Fitted.
  - The entries were re-added by designator after the swap to managed parts.
  - A few stale entries under old part IDs may remain. They're harmless and can be tidied.
- **Not run (only on your request):** Annotate, Update PCB / ECO, compile with auto-fix.

---

## 6. ERC state
Last run: **19 violations** across the project, with no missing footprints. The ones on this sheet are expected until the FPGA sheet exists:
- `ETH_MDC`, `ETH_PHY_TX_P/N` and `ETH_PHY_RX_P/N` each have only one pin, because the FPGA end isn't drawn yet.
- "No driving source" warnings on ETH_PHY_RST_N, PHY_RX_P_C, PHY_RX_N_C and PHY_XTAL1 come from passive and bidirectional pins. They're harmless.

The other warnings belong to Sheet1–3.

---

## 7. Open items

From the sheet's VERIFY list:
1. Y501 C0 is 7 pF against the 5 pF limit: get a guarantee from Abracon, or check oscillator start-up on the first boards.
2. C510–C513 are 50 V: revisit if a hipot test is required.
3. Confirm the tab-direction strap (R513/R514) on the first board.
4. Compare decoupling and ferrites with MaxLinear's development board.
5. Check the MDIO pull-up value (1k5).
6. Check that the TPD4E05U06 parts on the reel match outline DQA0010A, not B. This part was built with the checks off.
7. The Bel jack's crosstalk is -35 dB against the ≥ 45 dB target. Accepted, since there's no long-cable 2.5G test.
8. Confirm the `0v97` rail name with whoever owns the power sheet.
9. U501's footprint is IPC-calculated, since there's no vendor land pattern. Have the PCB maker review it, especially the exposed-pad paste openings.

Outside this sheet:
- **FPGA sheet:** add the eight matching off-sheet connectors on the balls in 2.1, plus the XDC constraints.
- **0.97 V supply:** place the TPS62825A to feed `0v97`, meeting the sequencing in 2.4.
- **GTP reference clock** on MGTREFCLK0 or MGTREFCLK1.
- **Switch "Footprint vs drawing" back on** in the eda-agent Config tab.
- **Optional:** tidy the stale variant entries, then annotate and update the PCB when you're ready.

---

## 8. Tool lessons (for future edits)
- `sch_draw_template` orientations are **quarter turns (0–3)**, not degrees. Degrees crashed Altium.
- After a crash, check which document is active before using any "active document" tool. Once, ports and directives landed in a library symbol by mistake.
- Run `sch_reload_document` before trusting compiled nets. Compiled nets can be stale.
- Parts get moved by hand in Altium, so read current positions before re-placing anything.
