# HUB75 RGB LED Matrix – DE2-115 FPGA Demo

This repository contains Verilog modules for driving a 32×32 or 64×32 HUB75 RGB LED matrix panel using the **DE2-115 FPGA board**.  
Two display modes are included:

1. A **UAH logo / color pattern renderer**  
2. A **GIF animation renderer**, using a HEX frame buffer generated externally

This project demonstrates how to interface a HUB75 panel using row addressing, color bitplanes, OE, LAT, and CLK timing signals.

---

## Repository Contents

Below are the files included in this project and their roles.

### Project Files

**de2_115_hub75_top.qpf**  
Quartus project file.

**de2_115_hub75_top.qsf**  
Pin assignment and device configuration file for the DE2-115.  
Defines mapping for:
- HUB75 signals (R1/G1/B1, R2/G2/B2, A/B/C/D row selects, CLK, LAT, OE)
- Clock source  
- Any debugging pins

---

## Top-Level Modules

### **de2_115_hub75_top.v**  
Primary top-level module for the HUB75 display.  
Responsibilities:
- Drives all HUB75 interface signals  
- Contains the state machine for refreshing rows  
- Instantiates one of the active renderer modules (`hub75_col_uahlogo` or `hub75_gif`)  
- Manages:
  - CLK toggling for pixel shift  
  - LAT latching  
  - OE blanking  
  - Row selection addressing  

This is the file Quartus compiles into the FPGA bitstream.

---

## Rendering Modules

### **hub75_col_uahlogo.v**  
Renderer for a static or color-cycling image (UAH logo or gradient pattern).  
- Fills panel with color patterns  
- Used for initial testing to confirm wiring, timing, and panel functionality  
- Good first step before loading GIFs or complex animations  
- Drives pixel color outputs based on row/column counters  

Useful for debugging: confirms that HUB75 data, OE, LAT, and CLK wiring are correct.

---

### **hub75_gif.v**  
GIF animation engine for the HUB75 panel.  
Features:
- Reads pixel data from a frame buffer ROM  
- Steps through animation frames  
- Handles per-frame display timing  
- Can animate 2D GIFs that were pre-converted to RGB565 or 24-bit packed data  

This module uses `gif_rom.v` + your generated HEX file as its memory source.

---

## Memory Modules

### **gif_rom.v**  
Simple synchronous ROM wrapper.  
- Loads a GIF frame buffer from a `.hex` file  
- Supplies pixel data to `hub75_gif.v`  
- Uses a parameterized ROM depth and width  
- Implements Quartus ROM initialization via `readmemh` or `ram_init_file`  

### **myGIF_rgb3bpp.hex**  
The pre-converted GIF data file stored in the form expected by `gif_rom`.  
This file was generated externally using your Python converter script.  
Contains all animation frames in linear address order.

---

## How the HUB75 Driver Works

A HUB75 RGB matrix requires:

- **Shift registers** for pixel data per row  
- **Row address lines (A/B/C/D)** to select the active row pair  
- **CLK** to shift color bits into the drivers  
- **LAT** to latch one row’s worth of shifted bits  
- **OE** to enable/disable display output (used for PWM dimming)

The refresh flow for each row:
1. Select row address A/B/C/D  
2. Shift in R1/G1/B1 and R2/G2/B2 pixel bits while toggling CLK  
3. Pulse LAT to latch the row  
4. Enable OE for a short period  
5. Move to next row and repeat  

Your top-level module implements this state machine.

---

## Usage Modes

### **UAH Logo / Color Test Mode**  
- Loads `hub75_col_uahlogo.v`  
- Shows a stable static pattern or color animation  
- Ideal for validating panel wiring, connectors, 5V level shifters, and timing

### **GIF Playback Mode**  
- Loads `hub75_gif.v`  
- Uses the data from `myGIF_rgb3bpp.hex`  
- Plays a looped GIF on the entire panel  

---

## How to Build & Load

### 1. Download the repository

### 2. Open in Quartus
- Open `de2_115_hub75_top.qpf`  
- Ensure the project device matches the DE10-Lite (MAX 10 10M50DAF484C7G)

### 3. Select display mode
Inside `de2_115_hub75_top.v`, choose which renderer to instantiate:
- `hub75_col_uahlogo` for static test pattern  
- `hub75_gif` for animation playback  

### 4. Compile
Quartus → Processing → Start Compilation

### 5. Program the DE2-115
- Open Quartus Programmer  
- Load the `.sof` file  
- Click *Start*

---

## Hardware & Wiring Notes

- HUB75 panels use **5V logic**, while FPGA uses **3.3V**  
  → Requires level shifters (e.g., 74AHCT245)  
- Ensure correct orientation of ribbon cable (red stripe = pin 1)  
- Required connections:
  - R1/G1/B1, R2/G2/B2  
  - A/B/C/D row address lines  
  - CLK, LAT, OE  
  - 5V power supply capable of driving LED matrix current  

Failures such as half-lit rows, dim output, or flickering typically indicate:
- Incorrect row addressing  
- Wrong panel type (32×16 vs 64×32 vs 32×32)  
- Misaligned ribbon cable  
- Incorrect OE/LAT/CLK timing

---

## Converting GIFs to HEX

This project uses:
- A Python script that converts GIF frames into RGB data  
- Output is stored as `myGIF_rgb3bpp.hex`  
- This hex file is loaded by `gif_rom.v`

To update the animation:
1. Generate a new HEX file  
2. Replace the existing `myGIF_rgb3bpp.hex`  
3. Recompile and reprogram




