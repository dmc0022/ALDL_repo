# ALDL Hardware — Sensor Board

---

## Table of contents

* [What to commit (KiCad)](#what-to-commit-kicad)
* [Current issues & blockers](#current-issues--blockers)
* [What’s been done (changelog)](#whats-been-done-changelog)
* [Design notes](#design-notes)

---

## What to commit (KiCad)

**Commit**

* `*.kicad_pro`, `*.kicad_sch`, `*.kicad_pcb`
* Project symbol libs: `libs/symbols/*.kicad_sym` (including any `*-rescue.kicad_sym`)
* Project footprints: `libs/footprints/*.pretty/` with `*.kicad_mod`
* 3D models: `libs/3d/*.step` / `*.stp` 
* `sym-lib-table` 

---

## Current issues & blockers

> *Living list.* Use checkboxes; Move completed items into the **What’s been done** section below.

* [ ] Need to verify Net Capacitance for I2C SDA & SCL bus
* [ ] Need to verify Pull Up Resistors for I2C bus
* [ ] Need to Configure Alert# PIN

> Tip: You can also track these as GitHub Issues and link them here.

---

## What’s been done (changelog)

> *Summarize per Pull-Request*

* **2025‑10‑22:** Initial import  `Sensor_Board` KiCad projects (schematics + boards)

---

## Design notes

### File conventions
* Use hierarchical sheets for re‑usable blocks (e.g., `CAP1188.kicad_sch`).
---
## Contributing workflow
1. Create a branch: `git switch -c feature/<short-name>`
2. Make changes in KiCad; run **ERC/DRC** and fix errors where possible.
3. Stage & commit only the files listed under *What to commit*.
4. Push and open a **Pull Request** with a short description, screenshots of schematic/board if useful, and any open questions.

**Commit Message Style** (suggested)
```
feat(driver): add CAP1188 symbol + footprint; wire up I2C and IRQ
fix(sensor): correct net label mismatch on SDA/SCL
chore(libs): add 3D STEP for SN74AHCT245PW
```




