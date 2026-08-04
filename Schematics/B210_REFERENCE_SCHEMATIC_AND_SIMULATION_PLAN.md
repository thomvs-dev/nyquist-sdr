# B210 Reference Schematic Analysis and Custom SDR Schematic/Simulation Plan

**Target platform:** Xilinx Artix-7 XC7A200T + Analog Devices AD9361 + 2.5GbE
**Version-1 radio mode:** one receive channel and one transmit channel (1R1T)
**Control architecture:** host-controlled over Ethernet; no MicroBlaze/soft CPU
**Primary reference reviewed:** `b210 (1).pdf`, eight schematic sheets
**Document purpose:** define what must be designed, simulated, reviewed, and
verified before manufacturing the custom SDR PCB

---

## 1. Executive conclusion

The B210 is a valuable **reference architecture**, but it is not a schematic
that can be copied component-for-component for this project.

The B210 reference contains these major subsystems:

1. Reference-clock and PPS selection/distribution.
2. AD9361 RF transceiver and its digital connection to an FPGA.
3. Spartan-6 FPGA banks, power, configuration, and debug.
4. Cypress FX3 USB 3.0 controller and a parallel GPIF bus to the FPGA.
5. Wideband RF matching, baluns, switches, amplifiers, and SMA ports.
6. Multi-rail power generation and sequencing.

Our design keeps the same **functional partitioning**, but changes the two
central digital blocks:

```text
B210:       AD9361 <-> Spartan-6 FPGA <-> FX3/GPIF <-> USB 3.0 host

Custom SDR: AD9361 <-> Artix-7 FPGA <-> 2.5GbE MAC/PCS/PHY <-> host PC
```

Therefore:

- Reuse the B210's sheet organization, control concepts, clock strategy, RF
  design method, test-point philosophy, and power-domain separation.
- Redesign all FPGA pin assignments, FPGA power, configuration, and
  decoupling for the exact XC7A200T package.
- Delete the FX3 and GPIF/USB subsystem.
- Add a complete 2.5GbE physical interface; Ethernet is not built into a bare
  Artix-7 device.
- Implement the AD9361 sample interface as source-synchronous DDR LVDS for the
  custom board, even though the B210/UHD implementation uses its own selected
  electrical mode and pin mapping.
- Start with 1R1T for the bandwidth and implementation risk target, while
  deciding deliberately whether unused second-channel pins/RF paths should be
  routed for a later board revision.

Simulation must be performed **by subsystem**. There is no useful single
button that can prove an entire RF, power, FPGA, and 2.5GbE schematic correct.
SPICE, S-parameter, IBIS/IBIS-AMI, timing, power-integrity, and thermal analyses
answer different questions.

---

## 2. Decisions that must be frozen before drawing the schematic

Do not assign FPGA pins or copy RF values until the following entries are
approved.

| Decision | Required output | Why it blocks design |
|---|---|---|
| Exact FPGA ordering code | Full XC7A200T part, package, speed and temperature grade | Determines pins, banks, transceivers, voltages and configuration options |
| 2.5GbE medium | SFP/2500BASE-X **or** RJ45/2.5GBASE-T | Selects GTP/PCS versus an external copper PHY, magnetics, clocks and power |
| RF frequency range | Minimum/maximum operating frequency and performance targets | Determines AD9361 input/output path, baluns, matching and switches |
| RF connector topology | Separate RX/TX or shared TX/RX plus RX-only port | Determines antenna switching, isolation and protection |
| Channel policy | Physical 1R1T only or route both AD9361 channels for future use | Changes FPGA I/O, RF components, PCB area and cost |
| Maximum complex sample rate | RX and TX rates and sample format | Determines Ethernet headroom, FIFOs and clocking |
| Reference options | On-board reference only, external 10 MHz/PPS, or GPSDO provision | Determines mux, PLL, connectors and control GPIO |
| Input power | Connector and allowed voltage range | Determines protection and regulator topology |
| PCB stack-up | Layer count, materials, controlled impedances and copper weights | Required for RF, LVDS and GTP routing and power integrity |
| Configuration method | QSPI flash density, JTAG connector and optional network update | Determines FPGA mode pins and boot circuitry |

### Recommended version-1 choices

- One active RX and one active TX channel.
- AD9361 dual-port, full-duplex DDR LVDS interface.
- Static IP/MAC initially, UDP control and sample transport, no FPGA CPU.
- SFP/2500BASE-X is the cleaner first 2.5GbE implementation if the selected
  host NIC and module support it; otherwise use a documented 2.5GBASE-T PHY
  reference design for RJ45.
- On-board low-jitter reference plus external 10 MHz and PPS connectors.
- JTAG plus QSPI boot flash; network FPGA update is a later milestone.

---

## 3. Sheet-by-sheet analysis of the B210 PDF

The PDF has eight physical pages. Its printed sheet numbering places the RF
sheet as 8/8 and power sheet as 7/8, so PDF page order and printed sheet number
are not identical at the end.

### PDF page 1 — clock and timing

Observed functions:

- External 10 MHz reference input and external PPS input.
- Optional GPSDO connections for 10 MHz, PPS, serial data, and lock status.
- ADF4001 PLL, VCTCXO, loop filter, and reference-source selection.
- Clock buffering/distribution to the FPGA and AD9361.
- PPS conditioning and FPGA control/status nets.
- A documented start-up sequence in which the controller initializes the
  transceiver/clock path and the FPGA controls the PLL.

What the custom design should retain:

- A clean reference source with independently filtered supply.
- An explicit selection method between local and external references.
- Separate clock, PPS, lock/status, and tuning/control nets.
- A differential clock delivered to a clock-capable FPGA input where required.
- Test points for the local reference, selected reference, AD9361 reference,
  FPGA reference, PPS, and lock indication.

What must change:

- Remove any initialization dependency on the B210 FX3 controller.
- Assign PLL/mux control to FPGA registers that the host can access over UDP.
- Recalculate the PLL loop filter if the reference oscillator, comparison
  frequency, or PLL part changes.
- Verify that the AD9361 reference amplitude, common mode, coupling, and jitter
  follow the selected reference architecture and AD9361 requirements.

Required analysis:

- Reference-frequency plan and ppm accuracy budget.
- Integrated phase-noise/jitter budget from source through every buffer.
- PLL loop stability/lock-time analysis using the selected vendor tool/model.
- PPS input threshold, ESD, edge conditioning and metastability handling.

### PDF page 2 — AD9361-to-FPGA interface

Observed functions:

- AD9361 data pins, data clocks, frame signals, SPI, reset, enable, TX/RX
  control, synchronization, gain-control inputs, and status outputs.
- AD9361 1.3 V domains and an interface-voltage domain.
- RBIAS using a precision resistor.
- Options for a local crystal/reference or an externally buffered reference.
- FPGA-bank pin mapping for the complete AD9361 digital interface.

The data path is source-synchronous DDR:

```text
RX:
AD9361 DATA_CLK + RX_FRAME + RX_DATA
    -> Artix-7 differential input buffers
    -> input delay/IDDR capture
    -> word/frame reconstruction
    -> RX FIFO and packetizer

TX:
TX sample FIFO
    -> word/frame formatter
    -> ODDR differential outputs
    -> TX_DATA + TX_FRAME
    -> forwarded FB_CLK
    -> AD9361 DAC datapath
```

Control is a separate low-rate path:

```text
Host UDP register command
    -> FPGA register router
    -> SPI master
    -> AD9361 SPI_CLK, SPI_DI, SPI_DO and SPI_ENB
```

Custom schematic requirements:

- Use the exact XC7A200T package pin table, not the Spartan-6 mapping.
- Put each LVDS P/N pair on a valid differential pair in one compatible I/O
  bank or in a deliberately verified bank grouping.
- Put `DATA_CLK` on clock-capable pins suitable for the chosen clocking method.
- Keep every P/N polarity explicit and consistent between schematic, XDC, HDL,
  and PCB constraints.
- Power the selected FPGA I/O bank at the voltage required by the selected
  AD9361 interface standard.
- Provide the termination and common-mode arrangement required by the AD9361
  and Artix-7 LVDS specifications; do not add termination by habit.
- Route reset, SPI and mode/control pins with defined pull states so that the
  RFIC remains safe while the FPGA is unconfigured.
- Place the RBIAS resistor and RFIC decoupling exactly as required by the
  AD9361 layout guidance.
- Expose SPI, reset, clocks, frames, and at least one data pair to accessible
  test pads or a high-impedance debug strategy.

This page is the closest functional reference for the custom digital radio
interface, but the electrical mode and pinout must be re-derived for our board.

### PDF page 3 — FPGA control, debug and miscellaneous I/O

Observed functions:

- Another FPGA I/O bank and board control/status signals.
- Debug/header connectivity, LED controls, PPS, GPS signals, antenna switches,
  band-selection nets, and RF enable signals.

Custom implementation:

- Provide a standard JTAG header with correct voltage reference and buffering
  only if required.
- Provide UART/debug pads even though normal operation is CPU-less.
- Add LEDs for power-good, FPGA configured, Ethernet link/activity, PLL lock,
  RX overflow, and TX underflow where practical.
- Route PPS to a suitable FPGA pin and define its electrical standard.
- Route RF switch/band-select signals from FPGA GPIO with safe pull defaults.
- Make transmit-enable default OFF through reset and configuration.
- Reserve ILA debug through JTAG; a wide external logic-analyzer connector is
  optional and must not compromise high-speed routing.

### PDF page 4 — FPGA power

Observed functions:

- Spartan-6 core, auxiliary, I/O and ground pins.
- Distributed bulk, mid-frequency and high-frequency decoupling.
- Separation of FPGA supply domains.

This sheet cannot be reused electrically. For the Artix-7 design:

- Create a pin-by-pin power audit for the selected package.
- Include all required core, auxiliary, block-RAM, I/O-bank and configuration
  rails.
- Include the GTP analog rails when the Ethernet design uses a GTP lane.
- Obtain voltage, tolerance, ramp, sequencing and current requirements from the
  current Xilinx documentation and power estimate for the exact device.
- Design the decoupling network from the package and PCB PDN target impedance,
  not by copying B210 capacitor counts.
- Keep noisy switching nodes away from FPGA clocks, GTP reference clocks, the
  AD9361 synthesizer and RF traces.

Required outputs are an FPGA rail table, Xilinx Power Estimator report, regulator
margin table, decoupling map, and power-up/power-down reset timing diagram.

### PDF page 5 — Cypress FX3 and USB 3.0

Observed functions:

- Cypress CYUSB3014 FX3 controller.
- USB 3.0 SuperSpeed and USB 2.0 signals, connector and ESD protection.
- FX3 reference crystal, EEPROM, optional authentication device, supply rails,
  and level translation.

Disposition: **remove this entire functional block**. It belongs to the B210's
USB transport and is not part of the Ethernet SDR.

Replace it with one of the Ethernet blocks in Section 7. Do not retain FX3
rails, USB ESD, USB connector, USB crystal, GPIF support parts, or FX3 EEPROM
unless they serve a separately justified function.

### PDF page 6 — FPGA/FX3 GPIF and configuration

Observed functions:

- A wide 32-bit GPIF data bus, GPIF control lines, and interface clock.
- FX3-controlled FPGA configuration/status signals.
- FPGA mode straps, program/init/done, serial configuration, and UART signals.

Disposition:

- Delete all GPIF data/control nets and the FX3 configuration dependency.
- Replace the transport boundary with streaming buses between FPGA packet
  logic, MAC, and PCS/PMA.
- Retain the *functions* of JTAG, QSPI configuration, mode straps, `PROGRAM_B`,
  `INIT_B`, `DONE`, and debug UART, but implement them to Artix-7 requirements.
- Define pull-ups/pull-downs so configuration starts deterministically and no
  RF transmit path enables during configuration.

### PDF page 7 — RF interface

Observed functions:

- AD9361 receive and transmit RF ports.
- Multiple receive bands and transmit paths.
- RF switches, baluns/matching networks, DC blocks, amplifiers, bias networks,
  band-select controls, and SMA connectors.
- Shared TX/RX and receive-only antenna routing.

This page shows the **architecture** of a wideband front end, but its component
values are inseparable from the B210 PCB layout, stack-up, component models,
frequency plan and measured tuning.

For the custom 1R1T board:

1. Choose one AD9361 receive channel and one transmit channel.
2. Choose either separate RX/TX connectors or a shared TX/RX switch plus an
   optional RX-only connector.
3. Partition the required RF range into bands only if one broadband network
   cannot meet return loss, noise figure and output-power targets.
4. Select baluns and switches from current vendor parts with valid S-parameter
   data across the complete frequency range.
5. Include ESD protection whose capacitance and insertion loss are acceptable.
6. Define maximum safe input power and add limiting/protection if required.
7. Keep TX disabled by hardware default.
8. Add conducted test points/connectors only where they do not create RF stubs.

Do not claim B210-like 70 MHz-to-6 GHz performance until the custom RF network
has been simulated, laid out, fabricated, and measured on a VNA/spectrum
analyzer.

### PDF page 8 — system power

Observed functions:

- External and USB power inputs, protection and power-path selection.
- Switching regulators and low-noise LDOs.
- Separate FPGA, FX3, AD9361, clock, synthesizer and TX-amplifier rails.
- Enable/power-good sequencing and bulk/local decoupling.

Custom implementation:

- Remove all FX3-only rails and their load allowance.
- Add the Artix-7 and, if used, GTP rail set.
- Add the selected SFP module or 2.5GBASE-T PHY rail/current requirements.
- Preserve low-noise separation for the AD9361 synthesizer, RF analog blocks,
  clock source and reference buffers.
- Size every rail from a worst-case current budget with start-up, temperature,
  tolerance and transient margin.
- Generate a reset tree from valid power-good signals; a delayed timer alone is
  not sufficient evidence that all rails are in regulation.

---

## 4. Proposed custom schematic hierarchy

Use hierarchical sheets and named interfaces so design reviews can be performed
one subsystem at a time.

| Sheet | Name | Main content |
|---:|---|---|
| 00 | System overview | Block diagram, inter-sheet ports, design notes, revisions |
| 01 | Input power and protection | Connector, fuse/current limit, reverse polarity, surge/ESD, power switch |
| 02 | Regulators and sequencing | All rails, enables, power-good tree, current test points |
| 03 | Reference clock and PPS | Local oscillator, optional PLL/mux, external 10 MHz, PPS, buffers |
| 04 | Artix-7 power/configuration | FPGA power pins, decoupling, JTAG, QSPI, straps, reset |
| 05 | AD9361 power/control/reference | RFIC supplies, RBIAS, reset, SPI, GPIO, reference input |
| 06 | AD9361 digital LVDS | RX/TX data pairs, frame/clock pairs, FPGA banks and length classes |
| 07 | RX RF front end | Selected RX port(s), balun, matching, switches, ESD, connector |
| 08 | TX RF front end | Selected TX port, matching, gain/switching, bias, protection, connector |
| 09 | 2.5GbE physical interface | GTP/SFP or MAC-to-PHY/RJ45, clocks, MDIO/I2C, ESD, indicators |
| 10 | Board control and debug | EEPROM/board ID, LEDs, UART pads, fan/temp sensors, spare GPIO |
| 11 | Connectors and mechanical | Remaining headers, mounting holes, shields and chassis-ground strategy |

The accompanying HDL pin map and PCB constraint table must use the same signal
names as these sheets.

---

## 5. Power-tree design tasks

The following is a planning table, not final regulator selection. Final voltage
and tolerance values must be checked against the exact FPGA, RFIC, PHY/SFP and
clock-device data sheets.

| Load group | Rail class | Noise concern | Evidence required |
|---|---|---|---|
| Artix-7 core/BRAM | High-current low-voltage digital | Transient droop and PDN impedance | Power estimate, transient model, plane/decoupling analysis |
| Artix-7 auxiliary/config | Auxiliary digital | Configuration ramp and tolerance | Sequencing table and start-up plot |
| Artix-7 I/O banks | Per-bank VCCO | Must match connected I/O standards | Bank-voltage/pin audit |
| Artix-7 GTP | MGT analog rails, if used | Very sensitive to ripple/noise | Xilinx transceiver power guidance and ripple calculation |
| AD9361 analog/digital | RFIC supply domains | Synthesizer spurs, noise and coupling | AD9361 reference design comparison and load-transient results |
| AD9361 interface | Digital interface supply | Must match FPGA bank | Logic-standard audit |
| Clock/PLL/VCTCXO | Low-noise clock rail | Phase noise and reference spurs | Regulator noise integration and clock budget |
| RF gain/bias | RF analog rails | Noise, linearity and thermal dissipation | Bias simulations and worst-case power |
| SFP or copper PHY | Module/PHY rails | Inrush and link transients | Vendor reference design and worst-case module/PHY load |

Tasks:

- [ ] Create a worst-case load spreadsheet with typical, maximum, start-up and
  margin currents.
- [ ] Run the Xilinx power estimator using realistic toggle rates, clocks, GTP,
  BRAM/FIFO and temperature assumptions.
- [ ] Select switching preregulators and low-noise post-regulators.
- [ ] Verify regulator loop stability using the selected capacitors and their
  bias/temperature-dependent effective capacitance.
- [ ] Simulate line step, load step, start-up, shutdown and fault recovery.
- [ ] Verify monotonic rails and all required sequencing relationships.
- [ ] Calculate regulator, inductor, MOSFET, FPGA, PHY and RF-device thermal
  rise at worst case.
- [ ] Add current-measurement links or shunts to every major rail.
- [ ] Complete a capacitor voltage/temperature/aging derating review.

---

## 6. AD9361 interface schematic tasks

### 6.1 Digital sample interface

- [ ] Freeze dual-port full-duplex DDR LVDS as the version-1 mode.
- [ ] Build a signal table containing AD9361 ball, net name, direction, FPGA
  ball, bank, I/O standard, termination, clock relationship and PCB length
  class.
- [ ] Assign `DATA_CLK` to a valid clock-capable differential input.
- [ ] Assign `FB_CLK` to a valid differential output clock path.
- [ ] Assign RX/TX frame and data pairs without crossing incompatible banks.
- [ ] Confirm the chosen bank VCCO and AD9361 interface voltage are compatible.
- [ ] Define allowed intra-pair skew, clock-to-data skew and pair-to-pair skew.
- [ ] Add series/termination footprints only where analysis or vendor guidance
  requires them; optional footprints must not form harmful stubs.
- [ ] Create matching XDC constraints and an HDL top-level pin manifest during
  schematic capture, not after layout.

### 6.2 Control and safe state

- [ ] Connect SPI clock, chip-enable, MOSI and MISO to the FPGA register/SPI
  engine.
- [ ] Connect `RESETB`, `ENABLE`, `TXNRX`, `SYNC_IN`, gain-control and status
  pins required by the chosen mode.
- [ ] Define pull states for the unconfigured FPGA period.
- [ ] Ensure TX enable and external TX amplifier/switch controls default OFF.
- [ ] Add accessible reset/SPI debug points.
- [ ] Document AD9361 power-up, reset, SPI initialization and PLL-lock sequence.

### 6.3 RFIC power and reference

- [ ] Reconcile every AD9361 supply pin against the reference design checklist.
- [ ] Place RBIAS and all local bypass parts according to layout guidance.
- [ ] Choose crystal versus external-reference drive and populate only the
  validated network.
- [ ] Separate/clean the synthesizer/reference supplies as required.
- [ ] Review exposed pad, ground-via field and thermal escape layout.

Related implementation detail is in
`../Firmware/AD9361_ARTIX7_ADC_DAC_FPGA_INTERFACE.md`.

---

## 7. 2.5GbE schematic options

### Option A — SFP with 2500BASE-X

Typical path:

```text
Artix-7 GTP TX/RX
    <-> required AC coupling and controlled-impedance channel
    <-> SFP cage/module
    <-> fiber or compatible direct-attach connection
```

Required circuits/tasks:

- A GTP-capable XC7A200T package and correct transceiver quad selection.
- Qualified GTP reference clock source and power filtering.
- 100-ohm differential TX/RX routing and AC-coupling placement per the chosen
  transceiver/module reference design.
- SFP cage, connector, mechanical ground fingers and shield strategy.
- Module power filtering and inrush budget.
- `TX_DISABLE`, `TX_FAULT`, `RX_LOS`, `MOD_ABS` and I2C management signals.
- ESD protection selected for the applicable exposed low-speed pins.
- PCS/PMA and MAC implementation in FPGA.
- Confirmation that the host adapter and SFP module support the same 2.5G
  optical/electrical mode; 1G-only compatibility must not be assumed.

### Option B — RJ45 with an external 2.5GBASE-T PHY

Typical path:

```text
FPGA MAC/interface
    <-> selected PHY-side digital interface
    <-> 2.5GBASE-T PHY
    <-> magnetics/common-mode network
    <-> protected RJ45
```

Required circuits/tasks:

- Select a PHY that has a practical FPGA-side interface supported by the
  available Artix-7 resources and vendor documentation.
- Copy the PHY vendor's validated clock, strap, MDIO, reset, regulator,
  magnetics and termination design with only documented changes.
- Add RJ45 ESD, chassis-ground and shield treatment.
- Validate PHY thermal dissipation; 2.5GBASE-T devices can be significant loads.
- Confirm FPGA MAC/IP compatibility and licensing before schematic freeze.

### Selection recommendation

Prefer Option A for the first board when a compatible 2.5G SFP host path is
available. It maps naturally to an Artix-7 GTP lane and avoids the analog and
thermal complexity of a multi-gigabit copper PHY. Choose Option B only after a
specific PHY, FPGA interface and available vendor reference design are frozen.

In either case, the Artix-7 provides programmable logic and, in suitable
packages, serial transceivers. It does **not** provide a complete Ethernet port:
the physical connector/module or PHY, clocks, protection, power, MAC/PCS logic,
and packet logic must all be designed.

---

## 8. Simulation and verification plan

### 8.1 Schematic connectivity and rule checking

Tool class: KiCad/Altium/Cadence ERC and custom rule scripts.

- [ ] No unconnected power, ground, configuration or thermal-pad pins.
- [ ] Every FPGA pin matches its bank voltage and intended I/O standard.
- [ ] All differential P/N polarities are checked end-to-end.
- [ ] Power-input/power-output/passive pin classifications are reviewed.
- [ ] Pull states are defined for reset, configuration, Ethernet PHY/module and
  RF transmit controls.
- [ ] Net names match HDL/XDC and the PCB constraints spreadsheet.
- [ ] A second engineer performs a page-by-page checklist review.

Exit criterion: zero unexplained ERC errors and a signed pin/power audit.

### 8.2 Power simulation

Tool class: LTspice, SIMPLIS, PSpice, or regulator-vendor tools/models.

Simulate separately:

- Minimum/nominal/maximum input voltage.
- No-load, steady maximum load and fast FPGA/PHY load steps.
- Output capacitor tolerance, DC bias, ESR and temperature corners.
- Soft-start, rail sequencing, brownout, shutdown and repeated restart.
- Regulator loop stability or vendor-recommended stability evidence.
- Ripple transfer into RFIC, synthesizer and clock rails.

Exit criteria:

- All rails remain inside data-sheet limits at every modeled corner.
- Start-up and shutdown obey the required sequence.
- No current limit, saturation or component thermal limit is exceeded.
- Power-good/reset release occurs only after clocks and rails are valid.

### 8.3 Clock simulation/analysis

Tool class: clock-vendor phase-noise tool, PLL design tool and timing analysis.

- Combine oscillator, PLL, buffer and regulator-noise contributions.
- Verify reference amplitude, duty cycle, slew, common mode and termination.
- Calculate integrated jitter over the bandwidth relevant to the AD9361 and GTP.
- Simulate PLL lock/settling and check external-reference switching behavior.
- Define PPS synchronizer and timestamp uncertainty.

Exit criterion: documented phase-noise/jitter and frequency-accuracy margins for
the AD9361 sample clock and Ethernet transceiver reference.

### 8.4 AD9361-to-FPGA signal integrity and timing

Tool class: vendor IBIS models plus Vivado timing analysis.

- Simulate representative and worst-case LVDS pairs across process, voltage,
  temperature, PCB loss, termination and package models.
- Check eye opening, overshoot/undershoot, common mode and crosstalk.
- Create source-synchronous input/output delay constraints.
- Include AD9361 clock-to-output, FPGA input delay/IDDR, PCB skew and jitter.
- Verify both DDR edges and all supported sample-rate modes.
- Plan IDELAY/clock-phase calibration and AD9361 PN-pattern testing.

Exit criteria:

- Positive setup/hold margin at the implemented timing corners.
- Differential pairs meet electrical limits.
- A post-route timing report and hardware PN-test procedure exist.

### 8.5 RF simulation

Tool class: Keysight ADS, AWR, QUCS-S or another simulator supporting Touchstone
models; 2.5D/3D EM solver for layout-critical sections.

Use manufacturer `.s2p`, `.s3p` or other multiport data for baluns, switches,
filters, amplifiers, connectors and ESD parts. Include PCB transmission lines,
vias, launches and component pad parasitics.

Simulate:

- Input/output return loss and insertion/gain across frequency.
- Cascaded receive gain and noise figure.
- Transmit gain, P1dB/compression, current and expected output power.
- TX-to-RX and port-to-port isolation in every switch state.
- Amplifier stability and bias corners.
- Effects of component tolerances and selectable matching values.
- Connector launch, balun transition and RF switch area with EM extraction.

Exit criteria are numerical and must be defined before simulation: band edges,
return loss, gain, noise figure, output power, isolation and stability factor.
Final validation requires VNA, signal-generator, spectrum-analyzer and power
measurements; simulation is not a substitute for board characterization.

### 8.6 2.5GbE channel analysis

Tool class: Vivado transceiver tools, IBIS-AMI/channel simulator, and the
selected PHY/module vendor tools.

- Model GTP package, PCB traces, vias, AC capacitors, connector/cage or PHY.
- Check insertion loss, return loss, impedance discontinuities and crosstalk.
- Generate transmitter and receiver eye/bathtub margin where models permit.
- Verify the GTP reference-clock jitter budget.
- For RJ45, follow the PHY vendor's mandatory channel/magnetics compliance
  analysis rather than applying SFP assumptions.

Exit criterion: channel loss and eye/jitter results meet the selected PHY/PCS
requirements with margin, followed by hardware BER/link testing.

### 8.7 Thermal and mechanical verification

- [ ] Worst-case component power-loss table completed.
- [ ] FPGA junction estimate includes ambient and airflow assumptions.
- [ ] PHY/SFP cage and RF amplifier temperatures are checked.
- [ ] Thermal vias and copper spreading are defined.
- [ ] Connector spacing, shield cans, heatsink keep-outs and enclosure airflow
  are included in the mechanical model.

---

## 9. Testability requirements to place in the schematic

- Input-voltage and input-current measurement points.
- Test points or current links for every major regulator rail.
- Power-good, reset and FPGA `DONE/INIT` visibility.
- JTAG and QSPI programming access that works on an unbootable board.
- Local/reference clock and PPS observability with correct probe loading.
- AD9361 SPI, reset, enable, data-clock and frame observability.
- Ethernet reference clock, MDIO/I2C/status and module/PHY reset access.
- Loopback options supported by the AD9361, FPGA GTP/PCS and Ethernet PHY.
- LEDs or readable status registers for link, PLL lock, overflow, underflow and
  packet errors.
- RF connectors/calibration paths appropriate to conducted laboratory testing.

Avoid ordinary test-pad stubs on RF, GTP and fast LVDS nets unless the pad and
branch are included in signal-integrity analysis.

---

## 10. Development milestones and exit criteria

### Milestone S0 — requirements freeze

- [ ] Complete every decision in Section 2.
- [ ] Approve measurable RF, clock, Ethernet, power and thermal requirements.
- [ ] Approve exact critical parts and PCB stack-up.

Exit: signed system requirements and block diagram.

### Milestone S1 — reference-design capture

- [ ] Obtain current manufacturer reference schematics/layout guides for the
  exact FPGA package, AD9361, clock parts, regulators and PHY/SFP.
- [ ] Create a requirements-to-schematic checklist.
- [ ] Record every intentional departure from a reference design.

Exit: reference pack and design-decision log complete.

### Milestone S2 — power, clock and configuration sheets

- [ ] Complete input protection, all regulators, sequencing and reset.
- [ ] Complete oscillator/reference/PPS architecture.
- [ ] Complete FPGA power, JTAG and QSPI configuration.
- [ ] Run initial power and clock simulations.

Exit: no unexplained ERC errors; current and start-up budgets pass.

### Milestone S3 — AD9361 digital and control sheets

- [ ] Complete RFIC power/reference/control and LVDS interface.
- [ ] Complete FPGA pin/bank assignment and matching XDC skeleton.
- [ ] Complete source-synchronous timing budget and IBIS plan.

Exit: signed FPGA-bank and AD9361 pin audit with positive preliminary timing
margin.

### Milestone S4 — 2.5GbE sheet

- [ ] Freeze SFP versus copper PHY.
- [ ] Complete clocks, power, management, reset, connector and high-speed lane.
- [ ] Confirm required FPGA IP and host compatibility.
- [ ] Complete preliminary channel/jitter analysis.

Exit: Ethernet electrical/design-rule review passes.

### Milestone S5 — RF sheets

- [ ] Complete RX and TX topology and component selection.
- [ ] Import vendor S-parameter/nonlinear models.
- [ ] Run matching, gain/NF, power, isolation and stability simulations.

Exit: all pre-declared RF metrics pass in simulation with margin.

### Milestone S6 — full schematic review

- [ ] Cross-check every IC pin against the current data sheet.
- [ ] Cross-check every net against HDL/XDC and firmware register ownership.
- [ ] Review safe states, test points, programming and recovery paths.
- [ ] Complete BOM lifecycle, availability and derating review.
- [ ] Close or explicitly waive every ERC/review item.

Exit: schematic freeze approved for PCB layout.

### Milestone S7 — PCB-aware re-simulation

- [ ] Extract routed RF, LVDS, clock and GTP channels.
- [ ] Re-run SI/RF/PDN simulations with actual stack-up and geometry.
- [ ] Run DRC, creepage/clearance, return-path and plane-split review.
- [ ] Review fabrication, assembly and controlled-impedance notes with the PCB
  manufacturer.

Exit: layout release package approved for fabrication.

### Milestone S8 — hardware validation plan

- [ ] Define staged current-limited power-up.
- [ ] Validate rails, sequencing, clocks, JTAG and QSPI before RFIC operation.
- [ ] Validate AD9361 SPI before digital streaming.
- [ ] Validate AD9361 PN patterns before real RF samples.
- [ ] Validate Ethernet PRBS/link/BER and UDP echo before UHD streaming.
- [ ] Characterize RF ports with calibrated laboratory equipment.

Exit: measured results are compared against each schematic/simulation
requirement, and discrepancies are tracked to closure.

---

## 11. Work-product checklist

The schematic phase is complete only when the repository contains:

- [ ] Editable hierarchical schematic sources.
- [ ] Reviewed schematic PDF.
- [ ] System block diagram and power tree.
- [ ] FPGA pin/bank spreadsheet and matching XDC skeleton.
- [ ] AD9361 control/sample-interface signal table.
- [ ] Worst-case rail/current/power budget.
- [ ] Clock-frequency and phase-noise/jitter budget.
- [ ] RF simulation project, vendor model archive, plots and pass/fail report.
- [ ] Power simulation files, model sources and corner plots.
- [ ] LVDS and 2.5GbE SI/timing reports.
- [ ] BOM with manufacturer part numbers, tolerances, ratings, lifecycle and
  alternates.
- [ ] PCB stack-up and impedance/length/skew constraint table.
- [ ] Design-decision log and unresolved-risk register.
- [ ] Manufacturing test and first-power-up checklist.

Every simulation report must record tool/version, model source, schematic
revision, assumptions, corner conditions, stimulus, numeric acceptance limits,
results and unresolved limitations. A screenshot without these items is not a
reproducible result.

---

## 12. Items not to copy blindly from the B210

- Spartan-6 part, pinout, bank assignments, voltage assumptions or decoupling.
- FX3, GPIF, USB connector, USB protection, FX3 EEPROM/crystal or FX3 rails.
- FPGA configuration being driven by the USB controller.
- RF matching values, baluns, switches or amplifier bias without current models
  and custom-layout simulation.
- Regulator choices/compensation without the custom load and capacitor models.
- Any obsolete or unavailable component.
- Any differential-pair polarity, termination or clock pin assignment.
- The B210's channel count or sample-mode assumptions.
- A wideband performance claim derived only from schematic similarity.

---

## 13. Principal risks

| Risk | Consequence | Required mitigation |
|---|---|---|
| Wrong FPGA package/bank selection | Board cannot implement LVDS or GTP pinout | Freeze full part number and perform early pin/bank audit |
| Incomplete Ethernet physical design | No link or unstable 2.5G operation | Select exact SFP/PHY path and follow validated reference design |
| Copying B210 RF values | Poor matching, gain, NF, isolation or instability | Model custom parts/layout and leave tuning provisions |
| Inadequate rail budget/sequencing | Boot failure, RF spurs, resets or damage | Estimate, simulate and measure each rail |
| Clock phase noise or GTP jitter | Degraded RF performance or link errors | Maintain separate budgets and low-noise supply/layout strategy |
| LVDS timing/polarity error | PN failure and corrupt I/Q samples | Unified signal table, IBIS/timing analysis and PN-pattern test |
| Unsafe default TX controls | Unintended RF transmission during boot | Hardware pulls and enable gating default TX OFF |
| Treating simulation as sign-off | Layout/package effects escape review | Re-simulate extracted layout and perform measured validation |

---

## 14. Immediate next actions

1. Freeze the exact XC7A200T ordering code and development/package constraints.
2. Decide SFP/2500BASE-X versus RJ45/2.5GBASE-T.
3. Write the numeric RF requirements and select the version-1 connector
   topology.
4. Obtain the official AD9361 reference design files and current models for all
   RF path candidates.
5. Create sheets 00–04 first: overview, input power, regulators/sequencing,
   clocks/PPS, and Artix-7 power/configuration.
6. Create the FPGA pin/bank spreadsheet before drawing sheet 06.
7. Build executable power and clock simulations while those sheets are under
   review.
8. Draw the RF and Ethernet sheets only after their exact component/interface
   choices are frozen.

The project firmware milestones and the electrical design must remain aligned:
the schematic must expose every clock, reset, GPIO, SPI signal, Ethernet status
signal and test path required by the bring-up plan in `../Firmware/timeline.md`.
