# AD9361 1R1T LVDS Simulation Results

**Run date:** 2026-08-05

**Simulator:** Icarus Verilog 12.0

**Testbench:** `tb_nyquist_ad9361_lvds_1r1t`

**Samples per run:** 16 RX and 16 TX

## Nominal run

Result: **PASS**

- RX samples checked: 16/16.
- TX samples checked: 16/16.
- RX frame errors: 0.
- RX differential-complement errors: 0.
- All reconstructed I/Q values matched the source values.
- All serialized TX I/Q values matched the requested values.
- All packed words matched `{I[11:0], 4'b0, Q[11:0], 4'b0}`.

Evidence:

- `nominal_transcript.txt`
- `nominal.vcd`

Final message:

```text
SIM PASS: RX/TX DDR serialization, frame timing, differential complements,
          I/Q reconstruction and UHD 32-bit packing all verified.
```

## Frame-error injection run

Result: **PASS**

The testbench deliberately changed transfer 2 of sample 8 from the expected
frame value 0 to 1. The data still reconstructed correctly, and the framing
monitor reported exactly one error.

Evidence:

- `frame_error_transcript.txt`
- `frame_error.vcd`

Final messages:

```text
FAULT-INJECTION PASS: deliberate frame error detected
SIM PASS: RX/TX DDR serialization, frame timing, differential complements,
          I/Q reconstruction and UHD 32-bit packing all verified.
```

## Verification boundary

These results verify the AD9361 1R1T DDR wire protocol and UHD sample-packing
contract in a portable behavioral simulation. They are not Vivado timing,
Xilinx SERDES primitive, signal-integrity, or hardware validation results.
