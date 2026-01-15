# CAP1188 Capacitive Touch Sensor – DE10-Lite FPGA Demo

This repository demonstrates how to interface an Adafruit CAP1188 8-channel capacitive touch sensor with the DE10-Lite (Cyclone IV) FPGA board using I²C.  
The FPGA initializes the CAP1188, polls its touch status register, and drives:

- LEDR[7:0] on the DE10-Lite  
- External breadboard LEDs driven through the CAP1188 LED pins

Two modes are included:

1. Direct mode – LEDs turn on only while being touched  
2. Toggle mode – Each touch flips the LED state ON/OFF (latched)

---

## Repository Contents

### Project Files

**cap1188_demo_top.qpf**  
Quartus project file.

**cap1188_demo_top.qsf**  
Quartus Settings File with pin assignments and device configuration.

---

### Top-Level Verilog Modules

**cap1188_touch_to_leds_top.v**  
Momentary mode: LEDs are ON only while a touch is active.  
Features include CAP1188 initialization, status polling, and LED driving.

**cap1188_touch_to_leds_top_toggle.v**  
Toggle mode: Each new touch flips the LED state ON ↔ OFF and holds it.  
This mode is recommended for switch-like behavior.

---

### I²C Support Module

**gl2c_low_level_tx_rx.v**  
Low-level I²C master controller used for all CAP1188 communication:  
SCL generation, SDA direction control, START/STOP, ACK/NACK, and byte transfers.

---

### Test Module

**cap1188_idtest_top.v**  
Simple hardware test module that attempts to read CAP1188’s device ID.  
Use this if I²C appears unresponsive or wiring needs verification.

---

## How the System Works

1. **Initialization**  
   The FPGA writes CAP1188 registers:  
   - 0x71 – LED Output Type  
   - 0x73 – LED Polarity  
   - 0x72 – Sensor Input LED Linking  
   - 0x00 – Clear interrupt/latch bits  

2. **Polling Loop**  
   The FPGA repeatedly reads:  
   - 0x03 – Sensor Input Status  
   Then clears interrupt flags by writing 0x00 again.

3. **LED Output Logic**  
   Direct mode: LEDs = current touch bits.  
   Toggle mode: each rising edge flips a stored LED state bit.

Both DE10-Lite LEDs and external LEDs display the same behavior.

---

## Hardware Requirements

- DE10-Lite FPGA board  
- Adafruit CAP1188 touch sensor  
- Breadboard + jumper wires  
- 8 LEDs + resistors (330–2k Ω)  
- Shared 3.3V and GND  
- I²C pull-ups (usually included on the CAP1188 module)

---

## Wiring Overview

### Power
DE10-Lite 3.3V → CAP1188 VCC  
DE10-Lite GND → CAP1188 GND  
DE10-Lite GND → Breadboard GND

### I²C
DE10 GPIO (per .qsf assignment) → CAP1188 SDA  
DE10 GPIO (per .qsf assignment) → CAP1188 SCL  

### Breadboard LEDs  
Depending on LED polarity configuration:

Option A:  
3.3V → LED → resistor → CAP1188 LEDx pin

Option B:  
CAP1188 LEDx pin → resistor → LED → GND

Both work as long as polarity matches the initialization registers.

---

## How to Build & Program

### 1. Download the repository

### 2. Open in Quartus
- Open `cap1188_demo_top.qpf`  
- Verify device is MAX 10 10M50DAF484C7G

### 3. Compile the project
Processing → Start Compilation

### 4. Program the DE10-Lite
- Open Programmer  
- Select the output `.sof` file  
- Click Start

### 5. Select the top-level version
- Use `cap1188_touch_to_leds_top.v` for momentary mode  
- Use `cap1188_touch_to_leds_top_toggle.v` for toggle mode  

### 6. Test the system
Touch any wire connected to CAP1188 inputs C1–C8.  
LEDs on both the DE10-Lite and the breadboard should respond.

---

## Troubleshooting

- If DE10 LEDs work but breadboard LEDs do not:  
  Check LED polarity, resistor direction, LED wiring, and the CAP1188 LED register configuration.

- If nothing responds:  
  Verify SDA/SCL pins in the `.qsf` file, confirm CAP1188 address (0x28), ensure shared GND, check power, and test I²C with `cap1188_idtest_top.v`.

- If the CAP1188 always NACKs:  
  SDA/SCL may be swapped, missing pull-ups, or the address may differ.




