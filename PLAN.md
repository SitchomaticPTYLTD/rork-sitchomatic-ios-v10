# Full Screenshot System Overhaul

## Overview
Complete rewrite of the screenshot capture, storage, and viewing system to make it reliable, persistent, and user-friendly.

---

### **Features**

- **Reliable screenshot capture** — retries up to 3 times if capture fails, with a short rendering delay before each attempt to ensure the page is fully drawn
- **Disk persistence** — screenshots are automatically saved to disk via the existing cache service, so they survive app restarts and memory pressure
- **Smart blank detection** — lowered threshold so real pages aren't falsely flagged as blank; adds variance-based check alongside the existing uniformity check
- **Correct crop calculations** — fixes the crop math so the focus area actually matches what you configure in settings
- **Pinch-to-zoom screenshot viewer** — the full-screen screenshot view now supports pinch-to-zoom and drag to pan, so you can inspect fine details
- **Screenshot count badge** — session tiles and rows show the actual number of screenshots captured per check
- **Persistent screenshot gallery** — debug screenshots load from disk on app launch instead of being lost when the app restarts
- **Memory-efficient display** — thumbnails in lists/grids use compressed versions; full-resolution only loaded when viewing detail

---

### **Design**

- Full-screen viewer gets a dark background with pinch-zoom and double-tap-to-zoom gesture
- Screenshot cards in the gallery show a subtle status indicator (green checkmark, red X, or gray question mark) overlaid on the thumbnail corner
- Album cards show a stacked-photo effect with the count badge
- The correction sheet keeps its existing layout but with smoother image transitions

---

### **Changes by Area**

**Screenshot Capture (LoginWebSession)**
- Add a 300ms render delay before capture
- Retry capture up to 3 times on failure
- Log capture failures with error details
- Fix crop rect math to properly handle point-to-pixel conversion

**Screenshot Cache Service**
- Add ability to store/retrieve screenshots by check ID
- Add batch save for debug screenshots
- Add load-all method to restore screenshots on launch
- Add thumbnail generation (smaller JPEG for list views)

**Blank Screenshot Detector**
- Lower uniformity threshold from 97% to 95%
- Add pixel variance check as secondary signal
- Increase sample size for more accurate detection

**Automation Engine**
- Use cache service to persist every captured screenshot to disk
- Log screenshot dimensions and file size after capture

**View Model**
- Load persisted screenshots from disk on init
- Cap in-memory screenshots at 500, but keep all on disk
- Add method to load screenshot from disk on demand

**Full Screenshot Viewer**
- Replace basic ScrollView with pinch-to-zoom using MagnifyGesture
- Add double-tap to toggle between fit and 1:1 zoom
- Add share button to export screenshot

**Screenshot Tile & Card Views**
- Load thumbnail from cache instead of full image
- Show screenshot count per check in session rows
