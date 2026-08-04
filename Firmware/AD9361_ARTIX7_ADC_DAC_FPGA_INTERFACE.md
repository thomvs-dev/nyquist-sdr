# AD9361 ADC/DAC to Artix-7 FPGA Interface

## Codebase analysis and implementation specification for the custom UHD SDR

**Project:** XC7A200T + AD9361 + 2.5GbE + host-controlled UHD  
**Version-1 operating mode:** one receive channel and one transmit channel  
**Recommended digital interface:** dual-port full-duplex DDR LVDS  
**Processing architecture:** FPGA real-time datapath, host PC control, no soft-core CPU

---

## 1. Purpose

This document explains:

- What the AD9361 ADC and DAC produce and consume.
- How the AD9361 communicates with an FPGA.
- The difference between the SPI control path and sample-data path.
- How UHD's B200 FPGA source captures and transmits AD9361 samples.
- Which B200 modules can be reused for an Artix-7 design.
- Which B200 modules must be replaced.
- How to implement a new Artix-7 LVDS physical interface.
- How to connect reconstructed samples to the UHD radio core.
- Clock, reset, timing, buffering and verification requirements.

This is an implementation guide, but it does not replace the AD9361 reference
manual, the Artix-7 SelectIO documentation, the selected FPGA-package data, or
board-level signal-integrity analysis.

## 2. Primary references

### External authoritative references

- [AD9361 Reference Manual UG-570](https://www.analog.com/media/en/technical-documentation/user-guides/AD9361_Reference_Manual_UG-570.pdf)
- [Analog Devices AXI AD9361 HDL documentation](https://analogdevicesinc.github.io/hdl/library/axi_ad9361/index.html)
- [Analog Devices official HDL repository](https://github.com/analogdevicesinc/hdl)
- [FMCOMMS2/3/4 HDL project documentation](https://analogdevicesinc.github.io/hdl/projects/fmcomms2/index.html)

### Local UHD sources

- `uhd-master/uhd-master/fpga/usrp3/top/b200/b200.v`
- `uhd-master/uhd-master/fpga/usrp3/top/b200/b200_io.v`
- `uhd-master/uhd-master/fpga/usrp3/top/b200/b200_core.v`
- `uhd-master/uhd-master/fpga/usrp3/lib/radio_200/radio_legacy.v`
- `uhd-master/uhd-master/host/lib/usrp/b200/b200_impl.cpp`
- `uhd-master/uhd-master/host/lib/usrp/b200/b200_cores.cpp`
- `uhd-master/uhd-master/host/lib/usrp/common/ad9361_ctrl.cpp`
- `uhd-master/uhd-master/host/lib/usrp/common/ad9361_driver/`

## 3. The complete AD9361-to-host architecture

The AD9361 contains the RF mixers, analog filters, ADCs, DACs, digital filters,
frequency synthesizers and calibration circuits. The FPGA does not connect to a
raw standalone ADC bus. It connects to the AD9361's formatted digital baseband
interface.

```text
Receive:

RF input
 -> AD9361 RF receive chain
 -> mixer and analog filter
 -> internal ADC
 -> AD9361 digital receive filters
 -> 12-bit signed I/Q interface samples
 -> FPGA source-synchronous DDR capture
 -> channel and I/Q reconstruction
 -> DDC and decimation
 -> timestamp and CHDR/VITA packetization
 -> UDP/2.5GbE
 -> UHD host application

Transmit:

UHD host application
 -> UDP/2.5GbE
 -> CHDR/VITA packet parsing
 -> DUC and interpolation
 -> FPGA channel and I/Q serialization
 -> AD9361 source-synchronous DDR input
 -> AD9361 digital transmit filters
 -> internal DAC
 -> mixer and RF transmit chain
 -> RF output
```

The FPGA also has an independent slow-control path:

```text
UHD AD9361 driver
 -> UDP control request
 -> FPGA control endpoint
 -> FPGA SPI master
 -> AD9361 register
 -> FPGA SPI readback
 -> UDP control response
 -> UHD driver
```

## 4. Do not confuse SPI and sample data

| Interface | Purpose | Typical rate | Carries I/Q samples? |
|---|---|---:|---|
| SPI | Configuration, calibration and status | At most 50 MHz SPI clock | No |
| RX digital data | ADC-derived I/Q from AD9361 to FPGA | Sample-mode dependent | Yes |
| TX digital data | I/Q from FPGA to AD9361 DAC path | Sample-mode dependent | Yes |
| ENABLE/TXNRX | AD9361 enable-state-machine control | Event driven | No |
| CTRL_IN/CTRL_OUT | Real-time control/status options | Event/status driven | No |

SPI controls LO frequency, sampling clocks, analog bandwidth, gain, interface
mode, delays, calibrations and other RFIC state. It is not part of the streaming
datapath.

## 5. AD9361 SPI interface

### 5.1 Signals

For the recommended four-wire mode:

| AD9361 signal | FPGA direction | Function |
|---|---|---|
| `SPI_ENB` | Output | Active-low chip select |
| `SPI_CLK` | Output | Serial clock |
| `SPI_DI` | Output | FPGA-to-AD9361 data |
| `SPI_DO` | Input | AD9361-to-FPGA read data |

The AD9361 powers up in four-wire, MSB-first mode. UG-570 specifies a maximum
SPI clock of 50 MHz. Data is launched on rising edges and sampled on falling
edges. For initial bring-up, use a substantially lower clock, such as 5 to
10 MHz, until signal integrity and protocol operation are confirmed.

### 5.2 Transaction format

Each operation begins with a 16-bit instruction:

```text
Bit 15       : W/R, 1 = write and 0 = read
Bits 14:12   : number of data bytes minus one, supporting 1 to 8 bytes
Bits 11:10   : unused
Bits 9:0     : starting register address
```

The instruction is followed by one to eight data bytes. AD9361 registers are
8-bit wide.

### 5.3 UHD implementation

The B200 host driver creates a packet-backed SPI interface in
`host/lib/usrp/b200/b200_impl.cpp`:

```cpp
_spi_iface = b200_local_spi_core::make(_local_ctrl);

_codec_ctrl = ad9361_ctrl::make_spi(
    client_settings,
    _spi_iface,
    AD9361_SLAVENO
);
```

`b200_local_spi_core::transact_spi()` in `b200_cores.cpp` ultimately causes the
FPGA SPI core to execute the transaction.

### 5.4 Custom Ethernet implementation

The custom design should retain the UHD AD9361 driver but replace the USB
control transport:

```text
Host C++ ad9361_ctrl
 -> artix_sdr SPI interface
 -> versioned UDP request
 -> FPGA control FIFO
 -> SPI command registers/state machine
 -> AD9361
 -> response FIFO
 -> versioned UDP response
 -> host C++ caller
```

Required response information:

- Request sequence number.
- Success or timeout status.
- Readback data.
- Invalid-slave or invalid-length indication.
- FPGA protocol version.

## 6. AD9361 digital interface choices

The AD9361 supports CMOS and LVDS digital data modes.

| Property | CMOS | LVDS |
|---|---|---|
| Electrical signalling | Single ended | Differential |
| Data-port width | One or two 12-bit ports | Separate 6-pair RX and 6-pair TX buses |
| SDR support | Available in some modes | No; LVDS is DDR |
| PCB noise immunity | Lower | Higher |
| B200 implementation | Yes | No |
| Recommended for this custom board | Not preferred | Yes |

The final choice must be frozen before schematic and PCB routing. FPGA bank
voltage, pin placement, I/O standards and termination depend on it.

## 7. What UHD supplies: the B200 LVCMOS interface

### 7.1 B200 physical ports

`fpga/usrp3/top/b200/b200.v` exposes:

```verilog
input         codec_data_clk_p;
output        codec_fb_clk_p;
input  [11:0] rx_codec_d;
output [11:0] tx_codec_d;
input         rx_frame_p;
output        tx_frame_p;
```

Despite the `_p` suffixes on some clock/frame names, this B200 data-interface
implementation is configured as LVCMOS. The host driver explicitly returns:

```cpp
AD9361_DDR_FDD_LVCMOS
```

in `host/lib/usrp/b200/b200_impl.cpp`.

### 7.2 B200 receive capture

`b200_io.v` uses Spartan-6 `IDDR2` primitives on all 12 input pins. Its logical
mapping is:

```verilog
.Q0(rx_q[bit]),
.Q1(rx_i[bit])
```

Thus one half-cycle produces a 12-bit I word and the other produces a 12-bit Q
word. `RX_FRAME` is captured with another `IDDR2` and used to delineate channel
slots.

The code then creates:

```text
rx_i0[11:0]
rx_q0[11:0]
rx_i1[11:0]
rx_q1[11:0]
```

In SISO mode the selected sample is replicated to the two internal radio paths.
In the B210 build, frame-dependent logic reconstructs the two channel slots.

### 7.3 B200 internal sample format

`b200.v` maps each 12-bit AD9361 component into the upper bits of a signed
16-bit component:

```verilog
.rx_i0(rx_data0[31:20]),
.rx_q0(rx_data0[15:4])
```

and forces the unused bits to zero. The effective representation is:

```text
I16 = I12 << 4
Q16 = Q12 << 4

rx_data[31:16] = I16
rx_data[15:0]  = Q16
```

This is left justification, not ordinary sign extension. The numeric scaling
contract must remain consistent through FPGA conversion and UHD metadata.

### 7.4 B200 transmit generation

The B200 core provides 16-bit I and Q components. `b200.v` selects the upper
12 bits:

```verilog
.tx_i0(tx_data0[31:20]),
.tx_q0(tx_data0[15:4])
```

`b200_io.v` drives the 12 physical pins using `ODDR2`:

```verilog
.D0(tx_i[bit]),
.D1(tx_q[bit])
```

It also generates `TX_FRAME` and forwards a transmit feedback clock.

### 7.5 Why `b200_io.v` cannot be reused directly

It contains Spartan-6-specific clocking and I/O primitives:

- `IDDR2`.
- `ODDR2`.
- `BUFIO2`.
- `BUFGMUX` and Spartan-6 placement assumptions.

It also implements the B200's 12-bit LVCMOS physical bus, whereas the proposed
custom board uses six differential LVDS data pairs in each direction.

Use `b200_io.v` to understand:

- Receive versus transmit direction.
- I/Q component packing.
- Channel and frame handling.
- The boundary to `b200_core`.

Do not use it as the Artix-7 pin-level implementation.

## 8. Recommended Artix-7 LVDS physical interface

### 8.1 Required data signals

In dual-port full-duplex LVDS mode:

#### AD9361 to FPGA

| Signal | Direction | Purpose |
|---|---|---|
| `DATA_CLK_P/N` | AD9361 to FPGA | Source-synchronous receive clock |
| `RX_FRAME_P/N` | AD9361 to FPGA | Receive sample/frame delineation |
| `RX_D[5:0]_P/N` | AD9361 to FPGA | Six differential receive-data lanes |

#### FPGA to AD9361

| Signal | Direction | Purpose |
|---|---|---|
| `FB_CLK_P/N` | FPGA to AD9361 | Feedback transmit clock derived from `DATA_CLK` |
| `TX_FRAME_P/N` | FPGA to AD9361 | Transmit sample/frame delineation |
| `TX_D[5:0]_P/N` | FPGA to AD9361 | Six differential transmit-data lanes |

`DATA_CLK` is generated by the AD9361. `FB_CLK` is generated by the FPGA and
must be a feedback version of `DATA_CLK` with the same frequency and duty
cycle. UG-570 states that there is no required phase relationship between the
two, but transmit setup/hold at the AD9361 must be satisfied.

### 8.2 Why a 6-bit bus carries a 12-bit sample

Each signed 12-bit component is transmitted as two consecutive 6-bit words:

```text
First 6-bit word  = sample[11:6], the MSBs
Second 6-bit word = sample[5:0], the LSBs

sample12 = {word_msb[5:0], word_lsb[5:0]}
```

Data is two's-complement. Within each 6-bit word, lane 5 is the most
significant bit and lane 0 is the least significant bit.

### 8.3 1R1T ordering

For one receive and one transmit RF channel, the continuous LVDS order is:

```text
I[11:6], Q[11:6], I[5:0], Q[5:0], repeat
```

With 50% duty-cycle framing:

```text
FRAME = 1 for I_MSB and Q_MSB
FRAME = 0 for I_LSB and Q_LSB
```

This requires four DDR edges, or two complete interface-clock periods, per
complex I/Q sample.

### 8.4 2R2T ordering for future expansion

For two RF channels:

```text
I1[11:6], Q1[11:6], I1[5:0], Q1[5:0],
I2[11:6], Q2[11:6], I2[5:0], Q2[5:0], repeat
```

With 50% framing, FRAME is high for the four channel-1 words and low for the
four channel-2 words. This is eight DDR edges, or four complete interface-clock
periods, per two-channel sample group.

The version-1 interface should be written as a parameterized deframer so that
2R2T can be added without redesigning the physical capture.

## 9. Artix-7 receive implementation

Recommended receive pipeline:

```text
DATA_CLK_P/N
 -> IBUFDS
 -> receive clock buffer strategy
 -> interface clock

RX_D[5:0]_P/N and RX_FRAME_P/N
 -> IBUFDS per pair
 -> optional IDELAYE2 per signal
 -> IDDR or ISERDESE2
 -> rising/falling 6-bit words and frame bits
 -> frame-state machine
 -> MSB/LSB assembly
 -> I/Q and channel deinterleaving
 -> signed 12-to-16-bit conversion
 -> rx_valid and channel samples
```

### 9.1 Primitive choices

Typical Artix-7 resources are:

| Function | Candidate primitive |
|---|---|
| Differential data input | `IBUFDS` |
| Per-lane delay | `IDELAYE2` |
| Delay reference controller | `IDELAYCTRL` |
| Two-edge capture | `IDDR` |
| Wider serialization option | `ISERDESE2` |
| Regional/global clock distribution | `BUFIO`, `BUFR`, `BUFG` as justified by placement |

The final clock topology must be selected from the actual package, pin bank and
placement. Do not mechanically translate every Spartan-6 `BUFIO2` into a
similarly named 7-series primitive.

### 9.2 Proposed receive module interface

```verilog
module ad9361_lvds_rx_if (
    input  wire        reset,

    input  wire        rx_clk_p,
    input  wire        rx_clk_n,
    input  wire        rx_frame_p,
    input  wire        rx_frame_n,
    input  wire [5:0]  rx_data_p,
    input  wire [5:0]  rx_data_n,

    input  wire        mode_2r2t,

    output wire        radio_clk,
    output wire        rx_valid,
    output wire [15:0] rx_i0,
    output wire [15:0] rx_q0,
    output wire [15:0] rx_i1,
    output wire [15:0] rx_q1,

    output wire        frame_error,
    output wire        pn_error
);
```

The exact port form may change if the ADI interface-only module is reused, but
the logical contract should remain explicit.

### 9.3 Receive state machine

For 1R1T, a conceptual state machine is:

```text
WAIT_FRAME
 -> capture I_MSB
 -> capture Q_MSB
 -> capture I_LSB
 -> capture Q_LSB
 -> assemble I12 and Q12
 -> publish rx_valid for one internal sample event
 -> repeat
```

The implementation must use the captured FRAME sequence to establish and
continuously verify alignment. It must not assume that reset always begins on a
particular data word.

For 2R2T, extend the state machine with the four channel-2 word positions.

### 9.4 Sample conversion

To remain compatible with the B200 radio-core boundary:

```verilog
wire [15:0] i16 = {i12, 4'b0000};
wire [15:0] q16 = {q12, 4'b0000};
wire [31:0] rx0 = {i16, q16};
```

Because `i12` and `q12` are two's-complement, left justification preserves the
sign and gives the expected B200-like scale.

## 10. Artix-7 transmit implementation

Recommended transmit pipeline:

```text
tx0 = {I16,Q16} from radio core
 -> defined rounding/saturation or select [15:4]
 -> I12 and Q12
 -> 1R1T/2R2T interleaver
 -> MSB/LSB 6-bit word generator
 -> TX_FRAME generator
 -> ODDR or OSERDESE2
 -> OBUFDS
 -> TX_D[5:0]_P/N and TX_FRAME_P/N

DATA_CLK-derived clock
 -> forwarded-clock ODDR
 -> OBUFDS
 -> FB_CLK_P/N
```

### 10.1 Proposed transmit module interface

```verilog
module ad9361_lvds_tx_if (
    input  wire        reset,
    input  wire        radio_clk,
    input  wire        mode_2r2t,

    input  wire        tx_valid,
    input  wire [15:0] tx_i0,
    input  wire [15:0] tx_q0,
    input  wire [15:0] tx_i1,
    input  wire [15:0] tx_q1,

    output wire        fb_clk_p,
    output wire        fb_clk_n,
    output wire        tx_frame_p,
    output wire        tx_frame_n,
    output wire [5:0]  tx_data_p,
    output wire [5:0]  tx_data_n,

    output wire        tx_underflow
);
```

### 10.2 16-bit to 12-bit conversion

The simplest B200-compatible operation is:

```verilog
i12 = tx_i16[15:4];
q12 = tx_q16[15:4];
```

This truncates four LSBs. If rounding is later added, specify and test it so
that positive and negative saturation behavior is unambiguous.

### 10.3 Underflow behavior

The AD9361 interface cannot wait for an Ethernet packet. The FPGA must always
have the next transmit word when the active frame requires it.

Define underflow behavior explicitly:

- Output zeros, or a configured idle value.
- Set a sticky underflow status bit.
- Increment an underflow counter.
- Generate an asynchronous UHD event.
- Do not emit partially assembled I/Q samples.

## 11. Connection to `b200_core`

`b200_core.v` is the most useful UHD FPGA boundary. It exposes:

```verilog
input  [31:0] rx0;
input  [31:0] rx1;
output [31:0] tx0;
output [31:0] tx1;

input  [63:0] tx_tdata;
output [63:0] rx_tdata;
input  [63:0] ctrl_tdata;
output [63:0] resp_tdata;
```

The Artix LVDS interface should connect as follows:

```text
ad9361_lvds_rx_if {I16,Q16}
 -> rx0[31:0]
 -> b200_core/radio_legacy
 -> DDC
 -> RX framer
 -> rx_tdata[63:0]
 -> Ethernet packet adapter

Ethernet packet adapter
 -> tx_tdata[63:0]
 -> b200_core/radio_legacy
 -> TX deframer
 -> DUC
 -> tx0[31:0]
 -> ad9361_lvds_tx_if
```

For version 1:

```text
rx0 and tx0 = active
rx1         = defined inactive value
tx1         = ignored or zero
```

Do not leave unused sample inputs floating or unknown in simulation.

## 12. Processing inside `radio_legacy`

### 12.1 Receive

`radio_legacy.v` performs:

```text
rx[31:0]
 -> optional digital loopback selection
 -> ddc_chain
 -> rate-change strobe
 -> new_rx_framer
 -> timestamp/SID/sequence insertion
 -> CHDR/VITA 64-bit packet stream
```

The code expands each 16-bit component to the 24-bit DDC input by appending
eight zeros:

```verilog
.rx_fe_i({rx_fe[31:16], 8'd0}),
.rx_fe_q({rx_fe[15:0], 8'd0})
```

### 12.2 Transmit

The reverse path is:

```text
CHDR/VITA packet
 -> new_tx_deframer
 -> new_tx_control
 -> duc_chain
 -> tx_fe_i/tx_fe_q
 -> 16-bit I/Q output
 -> tx[31:0]
```

The existing code takes bits `[23:8]` from each 24-bit DUC output.

### 12.3 Artix-7 porting warning

The B200 instantiates `radio_legacy` with:

```verilog
.DEVICE("SPARTAN6")
```

Its DSP and generated IP dependencies must be inspected, regenerated or
replaced for Artix-7. Successful Verilog compilation alone does not prove that
the original Spartan-6 DSP implementation is portable.

## 13. Streaming handshake and the absence of ADC backpressure

The packet side uses an AXI-stream-like handshake:

```text
tdata  = packet word
tvalid = source has a valid word
tready = destination can accept a word
tlast  = final word in packet
```

A transfer occurs only when `tvalid && tready`.

The raw AD9361 receive interface is different: it has no `ready` signal. Once
the receiver is running, samples arrive according to `DATA_CLK` and FRAME.
Therefore:

- The receive interface cannot pause the ADC when Ethernet stalls.
- The design needs elastic buffering between radio and Ethernet domains.
- A full FIFO must produce a visible overflow event and counter.
- The selected sample rate must remain within sustained link capacity.

Similarly, the AD9361 transmit interface cannot tolerate arbitrary gaps during
an active frame. TX packets must be buffered before consumption.

## 14. Clock-domain architecture

At minimum, expect these clock domains:

| Clock domain | Source | Main users |
|---|---|---|
| AD9361 receive/interface clock | `DATA_CLK_P/N` | LVDS capture and radio datapath |
| AD9361 transmit forwarded clock | Derived from receive/interface clock | TX DDR outputs and AD9361 capture |
| Ethernet MAC/PCS clock | Ethernet subsystem | Ethernet frames and UDP packets |
| Control/bus clock | Board oscillator or derived clock | Register endpoint and SPI |
| IDELAY reference clock | Stable board clock, commonly 200 MHz where required | `IDELAYCTRL` |

### 14.1 Recommended rules

1. Treat `DATA_CLK` as source synchronous at the FPGA pins.
2. Keep DDR capture and initial deframing in the interface clock domain.
3. If the radio DSP uses the same clock, avoid an unnecessary CDC.
4. Cross between radio and Ethernet domains using asynchronous packet FIFOs.
5. Cross configuration bits using synchronizers or atomic handshakes.
6. Synchronize reset deassertion separately in every clock domain.
7. Never combinationally connect `valid/ready` across unrelated clocks.
8. Do not switch radio clocks using an uncontrolled fabric mux.

### 14.2 Clock stopping

The AD9361 can be configured to stop `DATA_CLK` during idle periods. Version 1
should normally keep the interface clock running because stopped clocks
complicate reset release, CDC status and timing logic. Add clock stopping only
after continuous-clock operation is completely stable.

## 15. Timing and XDC requirements

The exact XDC constraints depend on:

- Complete XC7A200T package.
- Selected I/O bank and VCCO.
- PCB lane lengths and skew.
- Interface rate.
- Selected `IDDR`/`ISERDESE2` clock topology.
- AD9361 programmable clock and data delays.

UG-570 gives key LVDS limits, including a minimum `DATA_CLK` period of
4.069 ns at the maximum interface rate, 1 ns TX setup to the AD9361's specified
capture edge, and 0 ns TX hold. It also specifies clock-to-data output-delay
ranges for receive data and frame. Use the actual revision of UG-570 during
constraint generation.

Required constraint categories:

- `create_clock` on the incoming differential data clock.
- Generated/forwarded clock relationship for `FB_CLK`.
- Input delays for RX data and RX frame relative to `DATA_CLK`.
- Output delays for TX data and TX frame relative to `FB_CLK`.
- Differential I/O standards and legal bank placement.
- IDELAY reference-clock definition.
- False-path or asynchronous-clock declarations only for genuine CDC paths.
- Maximum skew constraints where justified.
- Pin locations derived from the final schematic.

Do not copy numerical XDC delays from another board. Combine RFIC timing, PCB
delay/skew and FPGA I/O timing into a board-specific budget.

## 16. Two layers of programmable timing

The system can contain timing adjustments in two places:

### AD9361 internal delays

The UHD AD9361 client exposes:

```cpp
rx_clk_delay
rx_data_delay
tx_clk_delay
tx_data_delay
```

The common driver programs these into AD9361 interface-delay registers.

### FPGA per-lane delays

Artix-7 `IDELAYE2` can shift receive data/frame timing at individual pins.

### Policy

- Begin from a known ADI-supported timing configuration.
- Do not arbitrarily maximize both RFIC and FPGA delays.
- Sweep a controlled delay dimension using PN data.
- Find the complete passing window.
- Choose a point near its center.
- Record the selected values and window width.
- Repeat over rate, power cycle, FPGA build and temperature.

## 17. ADI `axi_ad9361` reuse options

Analog Devices' official `axi_ad9361` core supports Xilinx devices and includes:

- CMOS and LVDS physical interfaces.
- Programmable line delays.
- Receive PN monitoring.
- TX DDS/pattern generation.
- Loopback.
- Data formatting.
- Optional DC and IQ correction.
- AXI-Lite control/status.

There are two practical integration strategies.

### Strategy A: use the interface logic only

```text
ADI LVDS pin interface and PN/delay logic
 -> simple channel sample/valid signals
 -> adapter to {I16,Q16}
 -> UHD b200_core
```

This is the recommended starting point because UHD already supplies DDC, DUC,
time and packet framing. Avoid duplicating ADI and UHD DSP stages.

### Strategy B: use the full AXI AD9361 core

This gives more ADI features but requires:

- AXI-Lite register access through the UDP control plane.
- Careful removal or bypassing of duplicated DSP functions.
- An adapter from ADI channel-valid/data signals to UHD radio-core inputs.
- More integration and verification work.

No soft-core CPU is inherently required for either strategy. An RTL UDP-to-AXI
Lite bridge can provide register access if full AXI control is retained.

Pin the ADI HDL source to a tested release or commit and review the individual
source-file licenses before incorporating it into a distributable product.

## 18. Reset and initialization sequence

Recommended high-level order:

1. Verify all FPGA, GTP and AD9361 power rails.
2. Hold FPGA datapaths and AD9361 in reset.
3. Start stable board and AD9361 reference clocks.
4. Configure the FPGA.
5. Release control-domain reset.
6. Verify UDP register access.
7. Verify the FPGA SPI master using a known AD9361 register read.
8. Execute AD9361 hardware/software reset.
9. Configure reference clock and digital interface mode.
10. Configure 1R1T DDR LVDS and interface delays.
11. Initialize/calibrate the AD9361 through the UHD driver.
12. Wait for RF PLL locks and valid `DATA_CLK`.
13. Release the LVDS receive-interface reset synchronously.
14. Run PN alignment validation.
15. Release the radio DSP and packet stream.
16. Enable real RX/TX streaming only after the interface passes.

Do not release sample processing merely because the FPGA has configured. The
AD9361-generated clock may not yet be valid.

## 19. Verification plan

### 19.1 Stage 1: structural simulation

- Verify 1R1T word order.
- Verify MSB/LSB concatenation.
- Verify I/Q ordering.
- Verify FRAME-based alignment after arbitrary reset phase.
- Verify two's-complement negative values.
- Verify 12-to-16-bit scaling.
- Verify TX reverse serialization.
- Inject one-bit and one-edge errors and confirm detection.

Useful fixed samples:

```text
0x000  = zero
0x001  = smallest positive
0x7FF  = maximum positive
0x800  = maximum negative magnitude encoding
0xFFF  = -1
0x555 and 0xAAA = alternating-bit checks
```

### 19.2 Stage 2: SPI hardware test

- Read a known register repeatedly.
- Write/read a scratch-like safe configuration field where allowed.
- Reset the RFIC.
- Initialize through the UHD AD9361 driver.
- Verify RX and TX PLL lock.
- Change LO, gain, bandwidth and sample clock.

### 19.3 Stage 3: AD9361 PN test

- Enable an AD9361-supported receive PN pattern.
- Check each reconstructed component continuously.
- Sweep receive delays.
- Identify passing and failing regions.
- Confirm no channel or I/Q swap.
- Run for at least one hour at each qualified clock mode.

### 19.4 Stage 4: FPGA-generated TX pattern

- Generate deterministic I/Q words in the FPGA.
- Serialize through the TX LVDS interface.
- Use AD9361 digital loopback where suitable.
- Confirm the recovered receive sequence.
- Test TX FRAME alignment and underflow behavior.

### 19.5 Stage 5: UHD packet path

- Stream an FPGA counter before real RF samples.
- Verify CHDR sequence numbers and timestamps.
- Verify no component byte swap or host-endian error.
- Start at 1 MS/s.
- Increase to 10 MS/s and 30.72 MS/s.
- Attempt 61.44 MS/s only after lower rates are stable.

### 19.6 Stage 6: RF loopback

- Use a cabled TX-to-RX connection with sufficient attenuation.
- Transmit a low-level tone.
- Confirm frequency, amplitude trend and spectral shape.
- Do not directly connect a high-power TX signal to RX without attenuation.

## 20. Required counters and debug signals

Expose through FPGA status registers:

```text
rx_frame_count
rx_frame_error_count
rx_pn_error_count
rx_sample_count
rx_fifo_overflow_count
tx_sample_count
tx_fifo_underflow_count
tx_frame_count
spi_transaction_count
spi_timeout_count
radio_clock_present
interface_locked
last_bad_frame_state
```

Recommended ILA probes:

- Captured rising/falling RX data.
- Captured rising/falling RX FRAME.
- Deframer state.
- Assembled 12-bit I/Q.
- Converted 16-bit I/Q.
- `rx_valid`.
- TX interleaver state.
- TX 6-bit word and FRAME.
- FIFO write/read/overflow/underflow.
- SPI clock, chip select, MOSI and MISO.

## 21. Common failure signatures

| Symptom | Likely cause |
|---|---|
| I and Q exchanged | Edge or interleave state mapping reversed |
| Positive values correct, negative values wrong | Incorrect two's-complement extension/scaling |
| Every sample shifted by six bits | MSB/LSB word order reversed |
| Alternating good/bad samples | FRAME alignment or DDR-edge error |
| Channels swapped | Incorrect 2R2T frame interpretation |
| Sporadic PN errors | Marginal setup/hold, clock jitter or lane skew |
| PN perfect but RF spectrum wrong | DSP scaling, DDC/DUC, analog configuration or I/Q mapping |
| RX works only after some resets | Missing clock-valid/reset sequencing |
| TX periodic discontinuities | Ethernet/FIFO underflow |
| SPI reads all zeros | Wrong chip select, read direction, address or MISO connection |
| SPI reads unstable data | Wrong SPI edge, excessive clock or signal-integrity issue |

## 22. FPGA directory recommendation

```text
fpga/usrp3/top/artix_sdr/
|-- artix_sdr.v
|-- artix_sdr_core.v
|-- artix_sdr.xdc
|-- ad9361_if/
|   |-- ad9361_lvds_rx_if.sv
|   |-- ad9361_lvds_tx_if.sv
|   |-- ad9361_lvds_deframer.sv
|   |-- ad9361_lvds_framer.sv
|   |-- ad9361_pn_checker.sv
|   `-- ad9361_delay_control.sv
|-- control/
|   |-- udp_control_endpoint.sv
|   `-- ad9361_spi_master.sv
`-- sim/
    |-- tb_ad9361_lvds_rx_if.sv
    |-- tb_ad9361_lvds_tx_if.sv
    |-- tb_ad9361_pn_checker.sv
    `-- tb_ad9361_spi_master.sv
```

If ADI HDL is imported, preserve it as a separately identifiable dependency
rather than mixing modified third-party source invisibly with project RTL.

## 23. Definition of done for the ADC/DAC interface

The AD9361–FPGA interface is complete only when all the following are true:

- [ ] Exact FPGA package, pins, banks and VCCO are documented.
- [ ] PCB LVDS impedance and length matching are reviewed.
- [ ] SPI reads and writes are repeatable.
- [ ] UHD initializes and calibrates the AD9361 through host-controlled SPI.
- [ ] `DATA_CLK`, `FB_CLK`, RX FRAME and TX FRAME are correct.
- [ ] 1R1T receive PN testing passes at every supported rate.
- [ ] Delay passing windows are measured and centered.
- [ ] I/Q, MSB/LSB, sign and channel ordering are verified.
- [ ] TX digital loopback passes.
- [ ] RX overflow and TX underflow are detected and reported.
- [ ] Vivado timing closes with board-specific I/O constraints.
- [ ] CDC and DRC reports have no unresolved critical findings.
- [ ] Tests pass across repeated builds and power cycles.
- [ ] Real RF loopback works at the documented sample rates.
- [ ] Version-1 single-channel UHD RX and TX streaming passes sustained testing.

## 24. Final implementation recommendation

Use the following division:

```text
Analog Devices interface logic
    Artix-7 LVDS capture/output
    delay control
    frame reconstruction
    PN verification

UHD B200-derived logic
    internal {I16,Q16} sample contract
    DDC/DUC
    timekeeper
    stream control
    CHDR/VITA framing
    SPI-control architecture

Custom project logic
    UDP control endpoint
    2.5GbE transport
    asynchronous FIFOs
    error/status registers
    Artix-specific clocks, resets and XDC
```

The stable integration boundary should be:

```text
AD9361 interface side: signed 12-bit I/Q plus sample-valid events
UHD radio-core side:   32-bit {I16,Q16}
Network side:          64-bit CHDR/VITA packet streams
```

Keeping these boundaries explicit allows the AD9361 timing interface, radio
DSP and Ethernet transport to be simulated and debugged independently.
