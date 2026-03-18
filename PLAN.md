# iPad Optimization: Layout, Memory Management & Efficiency

## Features

### iPad Layout & Split View Improvements
- **Wider content columns** — The three-column split view will use a balanced layout that gives more space to the content and detail panels
- **Quick-action toolbar** always visible at the top of the detail panel with Run, Pause, Stop, and card count badges — no need to navigate to Dashboard for controls
- **Denser table view** on iPad — table rows become more compact, showing 50%+ more cards on screen at once
- **4-column tile grid** on iPad (up from 3) to better use the wider screen
- **Pointer hover effects** on table rows, card tiles, filter chips, and action buttons — feels native with trackpad/mouse

### Memory Tightening
- **Screenshot cap reduced** from 500 to 200 in-memory, with automatic eviction of oldest screenshots beyond the limit
- **Memory cache reduced** from 200 items to 80 in the screenshot cache service, with lower JPEG quality (0.45 instead of 0.6) for disk storage
- **WebView pool max reduced** from 10 to 6, and a new `trimPool()` method auto-drains idle webviews after batch completes
- **Log buffer capped** at 1000 entries (down from 2000), with the oldest entries dropped automatically
- **Session history (checks) capped** at 500 — oldest completed checks are pruned automatically as new ones arrive
- **Thumbnail cache eviction** — thumb cache limited to 100 entries with LRU eviction

### Higher Concurrency for iPad
- **iPad gets up to 16 concurrent sessions** (picker shows 1–16 on iPad, stays 1–8 on iPhone)
- The concurrency picker automatically detects iPad and offers the extended range

### Automatic Cleanup
- **Auto-purge expired cards** on every app launch (already partially done, now with a log message)
- **Auto-trim old logs** — Debug log entries older than 7 days are automatically removed on launch
- **Auto-trim stale screenshots** — Screenshots older than 3 days with no user override are purged on launch
- **Auto-drain WebView pool** when a batch finishes — releases all idle webviews to free RAM
- **Batch cleanup hook** — after every batch, old completed checks beyond 500 are trimmed

### iPad Multitasking
- Enable `UISupportsMultipleScenes` so the app works properly in Split View and Slide Over on iPad

## Design

- **Hover effects**: Subtle background highlight (teal at 8% opacity) on table rows, card tiles, and buttons when the pointer hovers — feels like a native iPadOS data browser
- **Compact table mode**: Row height reduced, font sizes slightly smaller for the dense table, giving a spreadsheet-like feel on iPad
- **Quick-action bar**: A horizontal bar pinned at the top of the detail column with pill-shaped status indicators (Running/Paused/Idle) and control buttons — uses the existing teal accent color with subtle backgrounds
- **Memory indicator**: A small "RAM" badge in Settings → Debug section showing current screenshot count, cache size, and WebView pool status

## Screens Changed

- **Content View** — iPad layout refinements: balanced column widths, quick-action bar in detail column
- **Saved Credentials View** — Denser table, 4-column tile grid, pointer hover on rows
- **Login Dashboard View** — iPad concurrency picker extended to 16
- **Live Batch Panel View** — Quick controls always accessible
- **Settings View** — Concurrency picker range based on device, memory stats in Debug section
- **Working Logins View** — 4-column tile grid on iPad
- **Login Session Monitor** — 4-column tile grid on iPad
- **WebView Pool** — Reduced pool size, auto-drain on batch end
- **Screenshot Cache Service** — Reduced memory limits, auto-cleanup of old screenshots
- **Automation ViewModel** — Log cap reduced, auto-trim checks, screenshot eviction, cleanup hooks after batch
- **PPSRSolo App** — Auto-cleanup tasks on launch (old logs, stale screenshots, expired cards)
