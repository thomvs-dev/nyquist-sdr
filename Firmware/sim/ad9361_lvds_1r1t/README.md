# AD9361 1R1T DDR LVDS Interface Simulation

This directory contains a portable protocol-level demonstration of the
Nyquist SDR AD9361-to-Artix-7 interface.

The simulation demonstrates:

- Six-bit differential DDR data transport.
- Four transfers per 12-bit complex sample: `I[11:6]`, `Q[11:6]`, `I[5:0]`,
  `Q[5:0]`.
- The 1R1T frame pattern `1100`.
- RX I/Q reconstruction.
- TX I/Q serialization.
- Differential P/N complement checking.
- UHD-compatible 32-bit packing: `{I[11:0], 4'b0, Q[11:0], 4'b0}`.
- A deliberate frame-error test proving that framing faults are detected.

## Run

From PowerShell:

```powershell
cd Firmware\sim\ad9361_lvds_1r1t
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_sim.ps1
```

The default simulator location is `C:\iverilog\bin`. Override it if needed:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_sim.ps1 -IverilogBin "D:\tools\iverilog\bin"
```

Expected terminal messages include:

```text
SIM PASS: RX/TX DDR serialization, frame timing, differential complements,
          I/Q reconstruction and UHD 32-bit packing all verified.
FAULT-INJECTION PASS: deliberate frame error detected
```

Waveforms and transcripts are written under `results/`.

Open a waveform using GTKWave:

```powershell
C:\iverilog\gtkwave\bin\gtkwave.exe results\nominal.vcd
```

Useful signals to display are:

- `rx_clk_p`
- `rx_frame_p`
- `rx_d_p`
- `rx_sample_valid`
- `rx_i`
- `rx_q`
- `rx_packed`
- `tx_frame_p`
- `tx_d_p`
- `rx_frame_error_count`

## Verification boundary

`nyquist_ad9361_lvds_1r1t_demo.sv` is a behavioral demonstration, not the
production FPGA PHY. It observes both clock edges in portable SystemVerilog so
that the protocol can be shown without Vivado libraries.

The production Artix-7 implementation must instantiate UHD's
`cat_io_lvds_dual_mode.v`, which uses `ISERDESE2`, `OSERDESE2`, `IDELAYE2`,
`IDELAYCTRL`, `IBUFDS`, and `OBUFDS`. It must pass the original UHD testbench,
Vivado timing analysis, AD9361 PN-pattern testing, and delay-tap calibration.
