# 🎮 FPGA Breakout Game – DE10-Lite + ILI9341 LCD

This project implements a hardware-accelerated **Breakout game** entirely in **Verilog**, running on a **DE10-Lite FPGA**, displayed on a **2.8" ILI9341 TFT LCD**, and controlled using a **FT6336 capacitive touch panel**.

No CPU or software is used — all rendering, physics, and input processing are handled in hardware.

---

## 📁 Project Structure

| File | Description |
|------|-------------|
| **LCD_driver_top.v** | Top-level module. Handles LCD driver, touch controller, main app FSM, Breakout state machine, and video pixel muxing. |
| **breakout_game.v** | Core game logic: ball physics, paddle movement, brick HP system, scoring, collisions, and game over detection. |
| **breakout_renderer.v** | Pixel-level renderer for the Breakout game (ball, paddle, bricks, score HUD, and Game Over screen). |
| **home_renderer.v** | HOME screen renderer showing the Breakout app icon. |
| **tft_ili9341.v** | SPI LCD driver that streams RGB565 pixel data to the ILI9341 panel. |
| **ft6336_touch.v** | I²C touch controller interface for the FT6336. Outputs touch coordinates and touch state. |
| **font4x7.v** | Small 4×7 bitmap font used for UI text (scaled to 8×14). |
| ***.hex** | Pre-converted RGB565 sprite and icon images. |
| **LCD_driver_top.qsf** | Quartus project configuration and full DE10-Lite pinout for the LCD and touch panel. |
| **LCD_driver_top.qpf** | Quartus project file. |

---

## 🕹 Breakout Game Overview

### **Paddle Control**
- Controlled by dragging anywhere on the touch screen.
- Touch Y is rotated into game X automatically.
- Paddle is clamped to the screen edges.

### **Ball Physics**
- 1 pixel per physics tick (≈120 Hz).
- Velocity in X and Y independently (−1, 0, +1).
- Bounces off walls and the paddle.
- Paddle bounce angle depends on where the ball makes contact.

### **Bricks**
- 6 rows × 8 columns = 48 bricks.
- Each row has different hit points:  
  - Rows 0–1 → 3 HP  
  - Rows 2–3 → 2 HP  
  - Rows 4–5 → 1 HP  
- Destroying a brick increments score.

### **Game Over Logic**
Game ends when the ball falls below the paddle.

The Game Over screen shows:
- **PLAY AGAIN** button  
- **QUIT** (return to home)

Touch uses *rising-edge detection* so holding your finger does not auto-click UI buttons.

---

## 📺 Display / Touch Hardware

### LCD (ILI9341)
- SPI-driven RGB565 pixel interface  
- Driver module handles initialization and pixel writes

### Touch Panel (FT6336)
- I²C communication  
- Polling-based controller inside `ft6336_touch.v`

### Orientation
The LCD is mounted horizontally, so:
- Horizontal game X comes from **touch_y**
- Vertical game Y comes from **inverted touch_x**

---

## ▶ Build Instructions

1. Open **Quartus Prime Lite**  
2. Load `LCD_driver_top.qpf`  
3. Ensure the `.qsf` is included (this contains all pin assignments)  
4. Compile (Ctrl+L)  
5. Program the DE10-Lite with the `.sof` file  
6. Connect LCD + touch breakout as wired in the `.qsf`  

The game will appear on boot with the HOME screen showing the Breakout icon.
