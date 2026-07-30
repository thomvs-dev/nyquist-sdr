Milestone 1: Board foundations
Implement and verify:
All power rails and sequencing.
AD9361 reference clock.
Artix configuration.
GTP reference clock.
Reset generation.
Static IP and MAC address.
FPGA debug ILA access.
Milestone 2: Ethernet only
Before UHD:
Link reaches 2.5Gbps.
ARP works.
Host can ping the FPGA, if ICMP is implemented.
UDP echo works.
Packet counters show no CRC errors.
Test both normal and jumbo MTU.
Milestone 3: Control path
Implement:
Host UDP register command
→ FPGA control endpoint
→ register router
→ response UDP packet
Test repeated reads/writes with sequence numbers and timeouts.
Milestone 4: AD9361 SPI
Connect control packets to the FPGA SPI master.
Test:
Read known AD9361 registers.
Hardware reset.
Device identification.
Reference clock configuration.
RX PLL lock.
TX PLL lock.
LO frequency changes.
Temperature readout.
Gain changes.
At this point, the host UHD AD9361 driver should control the RFIC without any FPGA CPU.
Milestone 5: AD9361 digital interface
Use AD9361 internal PN test patterns to verify:
DDR edge selection.
Input delays.
I/Q ordering.
Channel ordering.
Bit ordering.
RX frame alignment.
SISO and MIMO modes.
Stability across FPGA rebuilds and temperature.
Milestone 6: UHD discovery
Implement artix_sdr_find() and FPGA discovery response.
Success criterion:
uhd_find_devices --args "type=artix_sdr"
finds the board.
Milestone 7: UHD probe
Implement the property tree and AD9361 management.
Success criterion:
uhd_usrp_probe --args "type=artix_sdr,addr=192.168.10.2"
reports:
Product and serial.
FPGA compatibility.
Clock rate.
Two RX/TX channels.
Frequency ranges.
Gain ranges.
Bandwidth ranges.
Sensors.
Milestone 8: RX streaming
Start with:
One RX channel.
sc16.
Low sample rate such as 1 MS/s.
FPGA-generated counter/ramp.
Then AD9361 PN data.
Then real RF samples.
Only after zero packet-format errors should you increase the rate.
Milestone 9: TX streaming
Add:
One TX channel.
Sequence checking.
TX FIFO occupancy.
Underflow reporting.
Timed bursts.
AD9361 digital or RF loopback.
Milestone 10: MIMO and timing
Finally add:
Two-channel synchronized RX.
Two-channel synchronized TX.
PPS.
External reference.
Timed RX/TX commands.
EEPROM configuration.
Network FPGA image loading.
