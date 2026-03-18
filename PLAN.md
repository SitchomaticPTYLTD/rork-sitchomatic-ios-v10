# Step 1: iPad-First Layout & Multitasking


## What's Changing

Transform the app from a phone-first tab layout into a three-column iPad-optimized experience with full multitasking support.

---

### **Features**

- **Three-column layout on iPad** — Left sidebar shows navigation (Dashboard, Cards, Working, Sessions, Settings), middle column shows the card list or dashboard content, right column shows card detail or live log
- **Automatic fallback on iPhone** — Standard tab bar on smaller screens, three-column only on iPad
- **Spreadsheet-style table view** for cards on iPad — sortable columns (BIN, Brand, Number, Expiry, Status, Tests, Country) with tap-to-sort headers
- **3-column tile grid** in tile mode on iPad (vs 2-column on iPhone)
- **Keyboard shortcuts** — ⌘R to run tests, ⌘N to import cards, ⌘F to search, Space to pause/resume batch, ⌘. to stop
- **Split View & Slide Over support** — app resizes gracefully in all iPad multitasking modes
- **Live log panel** in the right column during batch runs — shows real-time log entries alongside card list

---

### **Design**

- Sidebar uses SF Symbols with teal accent, matching the existing dark theme
- Table view uses monospaced fonts for card numbers and BIN data, with alternating row backgrounds for readability
- Column widths adapt to available space — in Split View narrow mode, falls back to two-column or single-column automatically
- Sort indicators (chevrons) on table headers
- Status dots (green/red/teal/gray) in the table status column
- Card detail slides into the right column without navigation push (stays in context)

---

### **Screens / Layout**

- **iPad (full screen)**: Three columns — Sidebar | Card List/Dashboard | Detail/Log
- **iPad (Split View narrow)**: Two columns — collapses sidebar into toolbar button
- **iPhone**: Standard 5-tab layout (unchanged from current)
- **Card Table View (iPad)**: Full-width table with 7 sortable columns, row selection, swipe actions
- **Live Batch Panel**: When a batch is running, the right column shows live progress + scrolling log

---

### **What Stays the Same**

- All existing functionality, settings, and automation logic untouched
- Main menu landing screen unchanged
- All existing views continue to work — they're just hosted inside the new column layout on iPad
