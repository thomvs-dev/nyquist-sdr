# Artix-7 + AD9361 + 2.5GbE UHD SDR Development Roadmap

## 1. Project objective

Develop a host-controlled software-defined radio using:

- Xilinx Artix-7 XC7A200T FPGA.
- Analog Devices AD9361 RF transceiver.
- 2.5GbE connection to a host PC.
- UHD-compatible host driver and applications.
- One active RX and one active TX channel in version 1.
- A hardware design that preserves a later path to AD9361 2R2T operation.
- No MicroBlaze or other soft-core CPU in version 1.

The host PC performs RF configuration and stream control. The FPGA performs all
deterministic, high-rate processing and packet transport.

## 2. Version 1 scope

### Included

- Static FPGA IP and MAC address.
- Ethernet ARP and UDP support.
- Optional ICMP echo for bring-up.
- UDP device discovery.
- UDP register and SPI control.
- Host-controlled AD9361 initialization.
- One RX and one TX channel.
- `sc16` sample format.
- RX and TX timestamps.
- FPGA DDC and DUC.
- RX overflow and TX underflow reporting.
- 2.5GbE full-duplex transport.
- UHD discovery, probing, RX and TX applications.

### Deferred

- MicroBlaze.
- DHCP.
- Onboard Linux.
- Standalone operation without a host.
- Network FPGA image update.
- Full RFNoC/MPM architecture.
- Runtime web interface.
- Two simultaneous full-rate RX channels.
- Two simultaneous full-rate TX channels.
- Advanced autonomous hopping.

## 3. Top-level architecture

```text
Host application
    |
    v
UHD public API
    |
    v
Custom artix_sdr UHD device driver
    |
    +---- UDP discovery and control ----------------------------+
    |                                                           |
    +---- UDP RX/TX sample transport -----------------------+   |
                                                            |   |
                                                            v   v
                                               Ethernet MAC/IPv4/UDP
                                                            |
                                                    2.5GbE PCS/PMA
                                                            |
                                                      Artix-7 GTP
                                                            |
                                                   SFP or 2.5G PHY
                                                            |
                                                        Host NIC

FPGA sample path:

AD9361 RX DDR -> AD9361 interface -> B200-derived radio core
              -> DDC -> timestamp/framer -> CHDR/VITA -> UDP -> host

Host -> UDP -> CHDR/VITA -> TX deframer -> DUC
     -> AD9361 interface -> AD9361 TX DDR

FPGA control path:

Host UHD -> UDP command -> control endpoint -> register/SPI operation
         -> UDP response -> host UHD
```

## 4. Layer ownership and task distribution

The following ownership labels describe engineering roles. One engineer may own
multiple roles, but the interfaces and exit criteria should remain separate.

| Work package | Primary owner | Supporting owner | Main responsibility |
|---|---|---|---|
| WP0 System architecture | System lead | All leads | Freeze requirements and interfaces |
| WP1 Board and power | Hardware engineer | RF engineer | Power, clocks, reset, PCB and connectors |
| WP2 AD9361 RF hardware | RF engineer | Hardware engineer | RF paths, matching and AD9361 hardware |
| WP3 AD9361 digital interface | FPGA RF-interface engineer | RF engineer | LVDS DDR capture/output and PN validation |
| WP4 2.5GbE physical link | FPGA Ethernet engineer | Hardware engineer | GTP, PCS/PMA, SFP or external PHY |
| WP5 Ethernet and UDP | FPGA networking engineer | Host driver engineer | MAC, ARP, IPv4, UDP and buffering |
| WP6 FPGA radio core | FPGA DSP engineer | FPGA integration engineer | B200 core port, DDC/DUC, time and packet flow |
| WP7 FPGA control plane | FPGA control engineer | Host driver engineer | Register protocol, SPI, timed commands |
| WP8 UHD host driver | C++/UHD engineer | FPGA control/network engineers | Discovery, properties, AD9361 and streaming |
| WP9 Verification | Verification engineer | Every work-package owner | Simulation, test automation and regressions |
| WP10 Integration | System lead | All owners | Hardware bring-up and release qualification |

Every owner must provide:

- Source files.
- Interface documentation.
- A repeatable test procedure.
- Captured logs or reports.
- Known limitations.
- An explicit pass/fail result against the exit criterion.

## 5. Interfaces that must be frozen early

### 5.1 Network parameters

Initial defaults:

```text
Host IP:             192.168.10.1
SDR IP:              192.168.10.2
Subnet:              255.255.255.0
SDR MAC:             02:00:00:00:00:02
Discovery/control:   UDP 49152
Sample data:         UDP 49153
MTU test:            UDP 49158
Initial MTU:         1500
Target jumbo MTU:    9000, after normal MTU is stable
```

### 5.2 Sample representation

Initial internal representation:

```text
Complex sample width: 32 bits
Bits [31:16]:         signed 16-bit I
Bits [15:0]:          signed 16-bit Q
Over-the-wire format: sc16
Initial channels:     RX0 and TX0
```

The AD9361 native 12-bit sample alignment inside each 16-bit component must be
documented and tested. Do not leave sign extension or bit shifting implicit.

### 5.3 Control packet

The host and FPGA must share one versioned control-packet definition containing:

- Magic number.
- Protocol major and minor versions.
- Sequence number.
- Operation code.
- Register or peripheral address.
- Write data.
- Read data.
- Status/error code.
- Optional execution timestamp.

Minimum operations:

```text
DISCOVER
READ32
WRITE32
READ64
WRITE64
SPI_TRANSACTION
GET_DEVICE_INFO
GET_LINK_STATUS
GET_COUNTERS
RESET_RADIO
```

### 5.4 Streaming packet

Freeze:

- CHDR/VITA header format.
- Endianness.
- Stream identifiers.
- Timestamp format.
- Packet sequence counter.
- Samples per packet.
- RX overflow indication.
- TX underflow indication.
- TX flow-control mechanism.
- Maximum supported packet length.

The host and FPGA definitions must be generated from, or manually checked
against, a single authoritative protocol document.

## 6. Milestone roadmap

## M0 — Requirements and architecture freeze

**Primary:** System lead  
**Dependencies:** None

### Tasks

- [ ] Record the complete XC7A200T part and package number.
- [ ] Verify that the chosen package exposes usable GTP lanes.
- [ ] Select SFP/2500BASE-X or external 2.5GBASE-T PHY.
- [ ] Select the GTP and AD9361 reference-clock sources.
- [ ] Decide AD9361 LVDS mode and initial 1R1T configuration.
- [ ] Preserve PCB routing required for later 2R2T where practical.
- [ ] Set version 1 maximum RX and TX rates.
- [ ] Freeze clock-domain names and nominal frequencies.
- [ ] Freeze static IP, MAC and UDP ports.
- [ ] Freeze control and streaming packet formats.
- [ ] Produce a preliminary FPGA resource and bandwidth budget.

### Exit criterion

A reviewed architecture document contains no unresolved choice affecting FPGA
pinout, PCB routing, clocks, packet formats or host-driver interfaces.

---

## M1 — Board power, clock and reset foundations

**Primary:** Hardware engineer  
**Support:** RF engineer, FPGA integration engineer  
**Dependencies:** M0

### Tasks

- [ ] Implement Artix-7 power rails and sequencing.
- [ ] Implement GTP analog power rails and filtering.
- [ ] Implement AD9361 power rails and sequencing.
- [ ] Provide a clean AD9361 reference clock.
- [ ] Provide the selected GTP reference clock.
- [ ] Provide FPGA configuration flash and JTAG.
- [ ] Implement power-on reset and manual reset.
- [ ] Connect AD9361 `RESETB`, `ENABLE` and `TXNRX`.
- [ ] Provide FPGA ILA/debug access.
- [ ] Add voltage, clock and reset test points.
- [ ] Review differential-pair impedance and length constraints.
- [ ] Review GTP, AD9361 LVDS and reference-clock placement.

### Verification

- [ ] Measure every rail during startup.
- [ ] Measure FPGA, AD9361 and GTP reference clocks.
- [ ] Confirm successful FPGA configuration.
- [ ] Confirm reset assertion and deassertion order.
- [ ] Record current consumption before enabling the RFIC.

### Exit criterion

The FPGA configures repeatedly, all power rails and clocks meet their
requirements, and no device reports a power or reset fault.

---

## M2 — 2.5GbE hardware and GTP/PHY link

**Primary:** FPGA Ethernet engineer  
**Support:** Hardware engineer  
**Dependencies:** M1

### If using SFP/2500BASE-X

- [ ] Instantiate and constrain the Artix-7 GTP channel.
- [ ] Implement GTP reset sequencing.
- [ ] Implement 2500BASE-X PCS/PMA.
- [ ] Connect SFP `TX_DISABLE`, `TX_FAULT` and `RX_LOS`.
- [ ] Optionally connect SFP I2C.
- [ ] Verify that the host NIC supports the selected 2.5GbE link mode.

### If using an external 2.5GBASE-T PHY

- [ ] Implement the selected FPGA-to-PHY interface.
- [ ] Implement MDIO/MDC controller.
- [ ] Implement PHY reset sequencing.
- [ ] Configure advertisement and auto-negotiation.
- [ ] Read negotiated speed, duplex and link status.
- [ ] Verify PHY magnetics and RJ45 routing.

### Common verification

- [ ] Confirm GTP PLL lock and reset-done.
- [ ] Confirm PCS block/comma alignment.
- [ ] Run internal serial loopback.
- [ ] Run PRBS testing if available.
- [ ] Bring up a stable 2.5Gbps link with the host NIC.
- [ ] Count and expose alignment and decoder errors.

### Exit criterion

The 2.5GbE physical link remains up for at least one hour with no unexplained
alignment, decoder or link-reset errors.

---

## M3 — Ethernet MAC, ARP, ICMP and UDP echo

**Primary:** FPGA networking engineer  
**Support:** FPGA Ethernet engineer, verification engineer  
**Dependencies:** M2

### Tasks

- [ ] Implement or integrate the Ethernet MAC.
- [ ] Generate and verify Ethernet CRC.
- [ ] Check received Ethernet CRC.
- [ ] Implement MAC-address filtering.
- [ ] Implement frame-length validation.
- [ ] Add RX and TX packet FIFOs.
- [ ] Add frame, CRC, drop and FIFO error counters.
- [ ] Implement ARP response for the static SDR IP.
- [ ] Implement ICMP echo response if resources permit.
- [ ] Implement IPv4 header validation.
- [ ] Implement UDP parsing and generation.
- [ ] Implement UDP echo service.
- [ ] Add normal-MTU support first.
- [ ] Add jumbo-frame support after normal MTU is stable.

### Host tests

- [ ] Assign `192.168.10.1/24` to the dedicated host NIC.
- [ ] Verify the SDR MAC appears in the host ARP table.
- [ ] Ping `192.168.10.2` if ICMP is implemented.
- [ ] Send numbered UDP echo packets.
- [ ] Test minimum and maximum payload lengths.
- [ ] Test sustained bidirectional UDP traffic.
- [ ] Check for missing, corrupt, duplicate and reordered packets.

### Exit criterion

At least one hour of sustained UDP echo testing completes with zero unexplained
payload corruption and zero FPGA FIFO overflows at the agreed test rate.

---

## M4 — FPGA control endpoint and register map

**Primary:** FPGA control engineer  
**Support:** Host driver engineer  
**Dependencies:** M3, frozen control protocol from M0

### Tasks

- [ ] Implement control-packet parsing.
- [ ] Validate magic number and protocol version.
- [ ] Track and return sequence numbers.
- [ ] Implement register read/write operations.
- [ ] Implement compatibility registers.
- [ ] Implement device-information registers.
- [ ] Implement link and error-counter registers.
- [ ] Implement structured error responses.
- [ ] Protect against malformed or truncated packets.
- [ ] Give control responses priority over bulk sample traffic.
- [ ] Add independent control request and response FIFOs.
- [ ] Implement reset registers with safe behavior.

### Verification

- [ ] Read fixed identification registers.
- [ ] Write and read scratch registers.
- [ ] Execute at least 100,000 repeated transactions.
- [ ] Verify sequence-number matching.
- [ ] Inject invalid operations and packet lengths.
- [ ] Verify timeout and retry behavior from the host.

### Exit criterion

Register transactions are repeatable, versioned and protected against malformed
packets, with no request/response mismatches during the stress test.

---

## M5 — AD9361 SPI and slow-control bring-up

**Primary:** FPGA control engineer and UHD engineer  
**Support:** RF engineer  
**Dependencies:** M1, M4

### FPGA tasks

- [ ] Connect the B200-derived SPI core or a dedicated SPI master.
- [ ] Verify SPI clock polarity and phase.
- [ ] Verify chip-select timing.
- [ ] Connect AD9361 reset and mode-control signals.
- [ ] Expose RFIC lock and status signals.

### Host tasks

- [ ] Create custom AD9361 board-parameter class.
- [ ] Connect UHD `ad9361_ctrl` to the UDP-backed SPI interface.
- [ ] Define reference-clock frequency.
- [ ] Define 1R1T/2R2T capabilities.
- [ ] Define available RF paths and antennas.
- [ ] Define board-specific band edges and interface settings.

### Tests

- [ ] Read known AD9361 registers.
- [ ] Perform hardware and software reset.
- [ ] Initialize the RFIC from the host.
- [ ] Verify RX and TX PLL lock.
- [ ] Tune several RX and TX LO frequencies.
- [ ] Change gain and bandwidth.
- [ ] Read temperature/status information.
- [ ] Repeat initialization after FPGA and RFIC resets.

### Exit criterion

The host PC can initialize, tune and query the AD9361 exclusively through UDP
control and FPGA SPI, without a soft-core CPU.

---

## M6 — AD9361 digital sample interface

**Primary:** FPGA RF-interface engineer  
**Support:** RF engineer, verification engineer  
**Dependencies:** M1, M5

### RX tasks

- [ ] Instantiate differential input buffers.
- [ ] Implement programmable input delays.
- [ ] Implement DDR input capture.
- [ ] Decode `RX_FRAME`.
- [ ] Reconstruct I and Q samples.
- [ ] Reconstruct channel ordering.
- [ ] Sign-extend or align 12-bit AD9361 data to 16 bits.
- [ ] Implement a PN-pattern checker.

### TX tasks

- [ ] Implement I/Q and channel serialization.
- [ ] Implement DDR output generation.
- [ ] Generate `TX_FRAME`.
- [ ] Generate or forward the required feedback clock.
- [ ] Constrain output timing relative to the AD9361.

### Verification

- [ ] Test AD9361 PN sequence modes.
- [ ] Sweep programmable input delays.
- [ ] Select the center of the valid timing window.
- [ ] Detect swapped I/Q.
- [ ] Detect channel swapping.
- [ ] Detect bit reversal and incorrect sign extension.
- [ ] Detect incorrect DDR-edge selection.
- [ ] Test digital loopback.
- [ ] Repeat after multiple FPGA builds and power cycles.
- [ ] Repeat at minimum and maximum intended sample clocks.

### Exit criterion

The PN checker reports zero errors over the agreed long-duration test at all
supported version 1 sample clocks.

---

## M7 — Port B200-derived FPGA radio core to Artix-7

**Primary:** FPGA DSP engineer  
**Support:** FPGA integration engineer  
**Dependencies:** M4, M6

### Tasks

- [ ] Create `fpga/usrp3/top/artix_sdr/`.
- [ ] Port `b200_core.v` into the Vivado build.
- [ ] Remove the B200 USB/GPIF dependency.
- [ ] Replace Spartan-6-specific primitives.
- [ ] Regenerate or replace incompatible CoreGen DSP IP.
- [ ] Connect RX0/TX0 to the AD9361 interface.
- [ ] Leave RX1/TX1 disabled but structurally planned for later.
- [ ] Connect control and response streams.
- [ ] Connect DDC and DUC.
- [ ] Connect timestamp and PPS logic.
- [ ] Create Artix-7 clock-domain crossings.
- [ ] Add reset synchronizers for every clock domain.
- [ ] Add timing and CDC constraints.
- [ ] Add internal counter and waveform test sources.

### Exit criterion

Vivado synthesis, implementation, timing analysis, CDC checks and DRC complete
without unresolved critical warnings, and the internal test streams run in
hardware.

---

## M8 — Connect CHDR/VITA streaming to 2.5GbE

**Primary:** FPGA networking engineer  
**Support:** FPGA DSP engineer, UHD engineer  
**Dependencies:** M3, M7

### RX path

- [ ] Accept RX packets from the radio core.
- [ ] Preserve SID, timestamp and sequence information.
- [ ] Encapsulate packets in UDP/IP/Ethernet.
- [ ] Implement RX packet buffering.
- [ ] Count RX FIFO overflow and dropped packets.

### TX path

- [ ] Classify incoming sample packets.
- [ ] Validate destination SID and packet format.
- [ ] Remove Ethernet/IP/UDP encapsulation.
- [ ] Feed the radio-core TX packet stream.
- [ ] Implement TX packet buffering.
- [ ] Implement flow control or credit reporting.
- [ ] Report late packets and underflows.

### Arbitration

- [ ] Give control responses appropriate priority.
- [ ] Prevent control traffic starvation.
- [ ] Prevent one streaming direction from blocking the other.
- [ ] Define behavior when packet buffers fill.

### Exit criterion

FPGA-generated RX samples and host-generated TX samples cross the network with
correct headers, sequence numbers and timestamps at increasing test rates.

---

## M9 — Custom UHD device discovery and probing

**Primary:** UHD host driver engineer  
**Support:** FPGA control/network engineers  
**Dependencies:** M4, M5

### Source structure

Create:

```text
host/lib/usrp/artix_sdr/
|-- CMakeLists.txt
|-- artix_sdr_impl.hpp
|-- artix_sdr_impl.cpp
|-- artix_sdr_io_impl.cpp
|-- artix_sdr_ctrl_iface.hpp
|-- artix_sdr_ctrl_iface.cpp
|-- artix_sdr_cores.hpp
|-- artix_sdr_cores.cpp
`-- artix_sdr_regs.hpp
```

### Discovery tasks

- [ ] Add an `ENABLE_ARTIX_SDR` UHD build option.
- [ ] Add the new driver directory to UHD CMake.
- [ ] Implement UDP broadcast discovery.
- [ ] Implement `artix_sdr_find()`.
- [ ] Implement `artix_sdr_make()`.
- [ ] Register the device with UHD.
- [ ] Support explicit `addr=192.168.10.2`.
- [ ] Check FPGA protocol compatibility.

### Property-tree tasks

- [ ] Create motherboard identification properties.
- [ ] Expose FPGA compatibility version.
- [ ] Expose one RX and one TX frontend.
- [ ] Create frequency properties and ranges.
- [ ] Create gain properties and ranges.
- [ ] Create bandwidth properties and ranges.
- [ ] Create sample-rate properties.
- [ ] Create clock and time-source properties.
- [ ] Create lock and link sensors.
- [ ] Connect properties to AD9361 and FPGA controls.

### Exit criterion

These commands succeed and report correct values:

```powershell
uhd_find_devices --args "type=artix_sdr"
uhd_usrp_probe --args "type=artix_sdr,addr=192.168.10.2"
```

---

## M10 — UHD RX streaming

**Primary:** UHD host driver engineer  
**Support:** FPGA networking and DSP engineers  
**Dependencies:** M8, M9

### Tasks

- [ ] Create UDP zero-copy receive transport.
- [ ] Configure the RX packet streamer.
- [ ] Configure `sc16` conversion.
- [ ] Set SID and samples per packet.
- [ ] Connect RX stream commands.
- [ ] Configure FPGA DDC.
- [ ] Parse timestamps and sequence numbers.
- [ ] Detect and report overflow.
- [ ] Add continuous and finite-burst modes.

### Test order

- [ ] FPGA counter at 1 MS/s.
- [ ] FPGA counter at 10 MS/s.
- [ ] FPGA waveform at 30.72 MS/s.
- [ ] AD9361 PN samples.
- [ ] AD9361 digital loopback.
- [ ] Real RF input.
- [ ] Increase toward 61.44 MS/s only after lower rates are stable.

### Exit criterion

`rx_samples_to_file` records the requested number of valid samples with correct
metadata and no unexplained sequence gaps at the qualified version 1 rate.

---

## M11 — UHD TX streaming

**Primary:** UHD host driver engineer  
**Support:** FPGA networking and DSP engineers  
**Dependencies:** M8, M9

### Tasks

- [ ] Create UDP zero-copy transmit transport.
- [ ] Configure the TX packet streamer.
- [ ] Generate correct CHDR/VITA headers.
- [ ] Configure FPGA DUC.
- [ ] Implement start-of-burst and end-of-burst.
- [ ] Implement timed TX.
- [ ] Implement TX flow control.
- [ ] Parse asynchronous underflow/late-packet messages.

### Test order

- [ ] Send an incrementing sample pattern.
- [ ] Check sample data inside FPGA using ILA.
- [ ] Run AD9361 digital loopback.
- [ ] Run cabled RF loopback with attenuation.
- [ ] Generate a low-power CW tone.
- [ ] Increase rate only after underflow-free lower-rate testing.

### Exit criterion

`tx_waveforms` generates a spectrally correct output for the requested duration
without unexplained packet loss, late packets or underflows.

---

## M12 — Timing, sustained performance and release

**Primary:** System lead and verification engineer  
**Support:** All owners  
**Dependencies:** M10, M11

### Timing tasks

- [ ] Verify FPGA hardware time.
- [ ] Verify timed RX start.
- [ ] Verify timed TX start.
- [ ] Add PPS input support.
- [ ] Add external reference support if present.
- [ ] Test simultaneous RX and TX.

### Performance tasks

- [ ] Tune FPGA FIFO depths.
- [ ] Tune host UDP socket buffers.
- [ ] Test host NIC settings.
- [ ] Qualify MTU 1500.
- [ ] Qualify jumbo MTU.
- [ ] Run one RX channel at increasing rates.
- [ ] Run one TX channel at increasing rates.
- [ ] Run simultaneous full-duplex RX and TX.
- [ ] Record packet-loss and overflow limits.
- [ ] Test multiple host PCs or NICs if possible.

### Release tasks

- [ ] Archive Vivado utilization and timing reports.
- [ ] Archive CDC and DRC reports.
- [ ] Record FPGA and host-driver compatibility versions.
- [ ] Document host build procedure.
- [ ] Document FPGA build procedure.
- [ ] Document network configuration.
- [ ] Document recovery and debug procedures.
- [ ] Document verified rates and unsupported combinations.
- [ ] Tag the host and FPGA source revisions together.

### Exit criterion

A repeatable release package builds from clean sources and passes the complete
hardware regression at the documented supported rates.

## 7. Bandwidth acceptance limits

For `sc16`, each complex sample consumes four payload bytes:

```text
Payload bit rate = sample rate x channel count x 4 x 8
```

| Configuration | Raw sample payload | Version 1 decision |
|---|---:|---|
| 1 channel at 30.72 MS/s | 0.983 Gb/s | Required |
| 1 channel at 61.44 MS/s | 1.966 Gb/s | Target after optimization |
| 2 channels at 30.72 MS/s | 1.966 Gb/s | Later feature |
| 2 channels at 61.44 MS/s | 3.932 Gb/s | Not possible over 2.5GbE |

RX and TX use opposite directions of a full-duplex Ethernet link. One RX and
one TX stream can therefore run simultaneously, provided each direction stays
within its own practical link and host limits.

## 8. Repository work areas

### UHD host

```text
uhd-master/uhd-master/host/lib/usrp/artix_sdr/
uhd-master/uhd-master/host/lib/usrp/common/
uhd-master/uhd-master/host/lib/transport/
uhd-master/uhd-master/host/examples/
```

Primary references:

```text
host/lib/usrp/b200/       AD9361, radio properties and legacy streaming
host/lib/usrp/x300/       UDP discovery and network transport concepts
host/lib/usrp/common/     AD9361 driver and common control code
```

### FPGA

```text
uhd-master/uhd-master/fpga/usrp3/top/artix_sdr/
uhd-master/uhd-master/fpga/usrp3/lib/
```

Primary references:

```text
fpga/usrp3/top/b200/b200_core.v
fpga/usrp3/top/x300/x300_eth_interface.v
fpga/usrp3/lib/simple_gemac/
fpga/usrp3/lib/packet_proc/
fpga/usrp3/lib/vita_200/
fpga/usrp3/lib/radio_200/
fpga/usrp3/lib/control/
fpga/usrp3/lib/rfnoc/xport_sv/
```

External reference needed:

```text
Analog Devices HDL axi_ad9361 interface
```

Pin this external reference to a known commit. Do not allow an untracked latest
version to become part of the reproducible build.

## 9. Verification matrix

| Layer | Simulation | Bench test | Required evidence |
|---|---|---|---|
| Power/reset | Review | Oscilloscope | Rail and reset captures |
| GTP/PCS | PRBS/loopback | Live link | Error counters and link log |
| Ethernet MAC | Frame testbench | Packet capture | CRC and packet counters |
| ARP/UDP | Protocol testbench | Wireshark/host tool | Packet captures |
| Control | Malformed/stress packets | 100k transactions | Automated test log |
| AD9361 SPI | SPI model where possible | Register read/write | UHD and ILA logs |
| AD9361 DDR | PN testbench | AD9361 PN mode | Zero-error duration log |
| Radio core | RTL packet tests | Counter/waveform | Vivado and capture results |
| RX streaming | Host test | RF/input test | Sequence and overflow report |
| TX streaming | Host test | Spectrum/RF test | Underflow and spectrum report |
| Timing | Timestamp tests | PPS/timed burst | Timing measurements |
| Full system | Regression | Long-duration run | Release qualification report |

## 10. Project rules

1. Do not start UHD integration before UDP register access is stable.
2. Do not use real RF samples to debug basic packet formatting.
3. Do not increase sample rate before lower-rate tests have zero unexplained
   packet errors.
4. Do not declare the AD9361 interface stable without long-duration PN testing.
5. Do not route sample data through a soft-core CPU.
6. Do not add MicroBlaze until a documented requirement justifies it.
7. Do not finalize the PCB without confirming the exact FPGA package and GTP
   pin availability.
8. Do not claim 61.44 MS/s support until sustained host-to-hardware testing
   demonstrates it.
9. Keep FPGA and UHD protocol compatibility versioned.
10. Preserve logs, packet captures, Vivado reports and test commands for every
    milestone.

## 11. Immediate next actions

- [ ] Provide the exact XC7A200T part/package or development-board model.
- [ ] Select SFP/2500BASE-X versus external 2.5GBASE-T PHY.
- [ ] Identify the available GTP reference clock.
- [ ] Confirm the AD9361 board/module and its reference clock.
- [ ] Create the authoritative control/stream protocol document.
- [ ] Create the new FPGA `artix_sdr` top-level directory.
- [ ] Build a minimal GTP/PCS loopback design before integrating UHD.

