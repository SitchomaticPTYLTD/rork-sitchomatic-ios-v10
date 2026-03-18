# PPSR App Upgrade: Clean Up, New Main Menu, Batch Progress & Card Detail Refresh

## Changes Overview

Implementing 4 of the 5 recommended improvements (everything except notifications).

---

### 1. 🧹 Clean Up Leftover Dual-Mode References
- Fix the settings footer that still says "Changes apply to Joe, Ignition & PPSR" → change to "Changes apply to all PPSR sessions"
- Remove Joe/Ignition proxy references from `ProxyRotationService` (leftover index tracking, separate lists, `forIgnition` parameters)
- Clean up the `DualModeAppShortcuts` naming
- Remove any other stale references to the old dual-site mode

---

### 2. 🏠 Redesigned Main Menu
- Make PPSR the dominant hero card — takes up ~60% of the screen with a large icon, title, and animated gradient background
- Move Nord Config, IP Score Test, Debug Log, and Vault into a compact horizontal row of smaller icon buttons below the hero card
- Staggered entrance animations for each element
- Keep the dark theme with the existing background image

---

### 3. 📊 Real-Time Batch Progress Card
- When a batch test is running, show a rich progress card on the Dashboard replacing the simple banner:
  - **Circular progress ring** showing completion percentage
  - **Live counters**: Working / Dead / Requeued updating in real-time
  - **Cards tested vs remaining** (e.g. "34 / 120")
  - **Estimated time remaining** based on average test duration so far
  - **Elapsed time** counter
  - **Speed indicator** (cards per minute)
- Smooth numeric transitions for all counters
- The progress ring fills with teal as tests complete

---

### 4. 🎨 Card Detail Visual Refresh
- **Animated status indicator**: pulsing glow for "testing", checkmark animation for "working", subtle shake for "dead"
- **Quick-copy buttons** with haptic feedback for card number, pipe format, and BIN — each shows a brief "Copied" toast
- **Mini test history chart**: a small horizontal bar chart showing the last 10 test results (green = pass, red = fail) as a visual timeline
- **Context menu** on the card visual for quick sharing
- Smoother gradient on the card header with brand-matched colors
