# AD9361-to-Artix-7 Interface Using the UHD/USRP Architecture

## Implementation and simulation demonstration for Nyquist SDR

- **Target:** XC7A200T + AD9361 + 2.5GbE
- **Version-1 mode:** one RX channel and one TX channel
- **AD9361 interface:** dual-port full-duplex DDR LVDS, 1R1T timing
- **Control:** host UHD over Ethernet; no FPGA soft CPU

---

## 1. Implementation decision

The custom SDR will retain the USRP B210 internal sample and control contract,
but it will not copy the B210 physical I/O module.

```text
USRP B210:
AD9361 LVCMOS DDR -> Spartan-6 b200_io -> b200_core/radio_legacy -> FX3/USB

Nyquist SDR:
AD9361 LVDS DDR -> 7-series cat_io_lvds_dual_mode
                -> b200-compatible 32-bit radio sample
                -> radio_legacy configured for 7SERIES
                -> Ethernet/UDP transport
```

The B210 selects `AD9361_DDR_FDD_LVCMOS` and uses Spartan-6 `IDDR2`, `ODDR2`
and `BUFIO2`. Those primitives and the 12-wire single-ended interface are not
the correct physical implementation for the Artix-7 board.

UHD already contains a better implementation:

- `fpga/usrp3/lib/io_cap_gen/cat_io_lvds_dual_mode.v`
- `fpga/usrp3/lib/io_cap_gen/cat_io_lvds.v`
- `fpga/usrp3/lib/io_cap_gen/cat_input_lvds.v`
- `fpga/usrp3/lib/io_cap_gen/cat_output_lvds.v`

These modules support Xilinx 7-series SERDES, programmable I/O delays, frame
alignment, 1R1T, and 2R2T operation.

---

## 2. Physical signal interface

For dual-port full-duplex LVDS, the schematic must connect:

| Direction | Signals | Function |
|---|---|---|
| AD9361 to FPGA | `DATA_CLK_P/N` | Source-synchronous RX clock |
| AD9361 to FPGA | `RX_FRAME_P/N` | Identifies I/Q word positions |
| AD9361 to FPGA | `RX_D[5:0]_P/N` | Six DDR receive data lanes |
| FPGA to AD9361 | `FB_CLK_P/N` | Forwarded TX clock |
| FPGA to AD9361 | `TX_FRAME_P/N` | TX I/Q word-position framing |
| FPGA to AD9361 | `TX_D[5:0]_P/N` | Six DDR transmit data lanes |
| FPGA to AD9361 | SPI, reset and mode GPIO | Slow control and safe state |

The differential buses must use valid Artix-7 P/N pairs in a compatible I/O
bank and clock region. `DATA_CLK_P/N` must use a suitable clock-capable input.
The final termination arrangement must be checked against the AD9361 and
Artix-7 requirements; internal and external termination must not be applied
simultaneously without analysis.

---

## 3. 1R1T data sequence

One complex sample contains a signed 12-bit I value and signed 12-bit Q value.
The six LVDS lanes carry six bits on every clock edge:

| DDR transfer | Six-bit bus value | Frame |
|---:|---|---:|
| 0 | `I[11:6]` | 1 |
| 1 | `Q[11:6]` | 1 |
| 2 | `I[5:0]` | 0 |
| 3 | `Q[5:0]` | 0 |

Therefore:

```text
RX_FRAME = 1, 1, 0, 0, 1, 1, 0, 0, ...
RX_DATA  = Ihi, Qhi, Ilo, Qlo, Ihi, Qhi, Ilo, Qlo, ...
```

This sequence is taken from the UHD
`cat_io_lvds_dual_mode_tb.sv` `Burst` task. The same testbench expects the TX
frame sequence `8'b11001100` for two consecutive 1R1T samples.

---

## 4. FPGA receive path

The production RX PHY performs:

```text
IBUFDS
  -> optional IDELAYE2 for clock/frame/data centering
  -> ISERDESE2 DDR deserialization
  -> frame-pattern search/bitslip
  -> 12-bit I/Q reconstruction
  -> radio_clk domain
  -> UHD-compatible 32-bit sample
```

UHD's input module looks for the expected deserialized frame pattern and uses
`BITSLIP` until word alignment is achieved. It reports `rx_aligned` only after
the frame relationship is valid.

The reconstructed sample is packed exactly like B200:

```verilog
assign rx_sample = {rx_i[11:0], 4'b0000,
                    rx_q[11:0], 4'b0000};
```

This left-aligns each signed 12-bit value in its 16-bit UHD I/Q field.

---

## 5. FPGA transmit path

The reused radio core supplies a 32-bit sample:

```verilog
wire [11:0] tx_i = tx_sample[31:20];
wire [11:0] tx_q = tx_sample[15:4];
```

The production TX PHY performs:

```text
12-bit I/Q sample
  -> 1R1T word ordering
  -> OSERDESE2 DDR serialization
  -> OBUFDS data/frame outputs
  -> forwarded differential FB_CLK
  -> AD9361 DAC interface
```

Transmit outputs and external RF enable controls must remain disabled or in a
defined idle state while FPGA configuration, AD9361 initialization, or clock
alignment is incomplete.

---

## 6. Clocks and reset

The production interface requires:

1. `DATA_CLK_P/N` from the AD9361 for source-synchronous capture.
2. A stable 200 MHz reference for `IDELAYCTRL`.
3. A control/bus clock for delay registers, SPI, and Ethernet control.
4. A generated `radio_clk` for the UHD radio DSP and timestamp domain.

In UHD's dual-mode LVDS wrapper:

- 1R1T uses the higher `radio_clk_2x` rate.
- 2R2T uses `radio_clk_1x` and produces two simultaneous channel samples.
- FIFO logic maintains safe transfer when selecting the appropriate mode.

SERDES reset must assert asynchronously and deassert synchronously in the
associated divided-clock domain. `IDELAYCTRL` must become ready before sample
alignment is accepted.

---

## 7. Host and SPI control path

The control architecture follows B200:

```text
Host ad9361_ctrl
  -> uhd::spi_iface
  -> UDP register transaction
  -> FPGA register router
  -> simple_spi_core
  -> AD9361 SPI
```

The custom host parameter class must return:

```cpp
AD9361_DDR_FDD_LVDS
```

Version 1 must select:

```cpp
codec_ctrl->set_timing_mode("1R1T");
codec_ctrl->set_active_chains(true, false, true, false);
```

The existing UHD AD9361 driver already contains register programming for LVDS,
1R1T/2R2T timing, interface delays, RF tuning, filters, gain, calibration, and
PLL lock checking.

---

## 8. Portable simulation included in this repository

The runnable demonstration is located at:

```text
Firmware/sim/ad9361_lvds_1r1t/
```

It contains:

| File | Purpose |
|---|---|
| `rtl/nyquist_ad9361_lvds_1r1t_demo.sv` | Portable behavioral RX/TX interface model |
| `tb/tb_nyquist_ad9361_lvds_1r1t.sv` | Self-checking AD9361 source and FPGA output testbench |
| `run_sim.ps1` | Compile and run nominal and fault-injection tests |
| `results/nominal.vcd` | Passing waveform |
| `results/frame_error.vcd` | Waveform containing one deliberate frame error |
| `results/*_transcript.txt` | Reproducible console evidence |

Run from PowerShell:

```powershell
cd Firmware\sim\ad9361_lvds_1r1t
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_sim.ps1
```

The testbench sends 16 known RX samples, supplies 16 known TX samples, and
checks:

- All P/N signals remain complementary.
- Frame is `1100` for every sample.
- RX I and Q are reconstructed without bit swapping.
- TX I and Q are serialized without bit swapping.
- The packed word equals `{I, 4'b0, Q, 4'b0}`.
- RX/TX sample counters equal 16.
- Nominal frame and differential error counters remain zero.
- A deliberately corrupted frame bit increments the frame-error counter once.

---

## 9. What this simulation proves

The portable test proves the agreed digital protocol and internal sample
contract:

- Six-bit DDR sequencing.
- Frame timing.
- I/Q high/low-half ordering.
- Differential complement behavior.
- RX reconstruction.
- TX serialization.
- B200-compatible 32-bit sample packing.
- Basic framing-error detection.

It is appropriate for explaining the interface architecture and showing a
reproducible waveform to the project guide.

---

## 10. What it does not yet prove

The portable model intentionally does not instantiate proprietary Xilinx
simulation primitives. Therefore it does not prove:

- Artix-7 pin placement or I/O-bank legality.
- `ISERDESE2`/`OSERDESE2` primitive configuration.
- `IDELAYE2` tap values or calibration margin.
- Setup/hold timing after place and route.
- PCB skew, termination, signal integrity, or jitter.
- AD9361 electrical compliance.
- Operation on physical hardware.

These require the production UHD module, the exact XC7A200T package, Vivado
UNISIM simulation, XDC constraints, post-route timing, IBIS analysis, and
AD9361 PN-pattern hardware testing.

---

## 11. Production implementation tasks

- [ ] Freeze the exact XC7A200T package and LVDS pin bank.
- [ ] Add UHD `io_cap_gen` sources without removing their LGPL notices.
- [ ] Instantiate `cat_io_lvds_dual_mode` in `nyquist_ad9361_io.v`.
- [ ] Connect `a_mimo=0` and the selected TX channel for version 1.
- [ ] Add programmable input/output delay registers to the UDP control map.
- [ ] Generate and validate the 200 MHz `IDELAYCTRL` reference.
- [ ] Pack/unpack 12-bit samples using the B200 32-bit contract.
- [ ] Instantiate one `radio_legacy` with `DEVICE="7SERIES"`.
- [ ] Connect the radio AXI-stream ports to the Ethernet packet subsystem.
- [ ] Add `rx_aligned`, PN-error, overflow, underflow, and delay-tap readbacks.
- [ ] Implement the custom UHD `ad9361_params` class using LVDS.
- [ ] Port and run the original UHD LVDS dual-mode testbench in Vivado.
- [ ] Complete post-route timing for every supported sample rate.
- [ ] Sweep IDELAY taps using AD9361 PN patterns and select the center of the
  error-free window.

---

## 12. Demonstration sequence for the project guide

1. Show the four-transfer I/Q diagram in Section 3.
2. Run `run_sim.ps1` and show both `SIM PASS` messages.
3. Open `results/nominal.vcd` in GTKWave.
4. Display `rx_clk_p`, `rx_frame_p`, `rx_d_p`, `rx_sample_valid`, `rx_i`,
   `rx_q`, and `rx_packed`.
5. Zoom to one sample and show frame `1100` with I-high, Q-high, I-low,
   Q-low data.
6. Open `results/frame_error.vcd` and show `rx_frame_error_count` incrementing
   when the deliberate bad frame bit occurs.
7. Explain that the final hardware module is UHD's 7-series SERDES interface,
   while this portable model makes the protocol visible and reproducible now.
