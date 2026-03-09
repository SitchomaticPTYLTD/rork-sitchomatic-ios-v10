# Dual Find Account Mode — New Main Menu Entry

## Features

- **New "Dual Find" mode** accessible from a new button on the Main Menu screen
- **Toggle between 6 sessions (3+3) or 4 sessions (2+2)** via a segmented control in the setup screen
- **Import emails** by pasting a list (one email per line) into a text area
- **Enter 3 passwords** in 3 separate text fields
- **Fixed sessions** — the same sessions are reused for the entire run (no rotation)
- **Smart credential loop**: loads Password #1, runs through every email, then switches to Password #2, then Password #3 — clearing and replacing the email field each time, only clearing the password field between password rounds
- **Tests every email × password combination on both Joe Fortune and Ignition** simultaneously using the fixed sessions
- **Disabled account detection** — if "disabled" appears in the response, that email is permanently eliminated from all further testing on both platforms
- **Transient error handling** — on timeout (10s), "ERROR", "SMS", or no response, the session is burned and rebuilt, and only the current email+password combo is retried
- **Positive login detection** — uses the existing success detection (green banner, URL redirect); on success, the entire test pauses immediately
- **Save & resume** — on a successful hit, the exact position (email index, password number, platform) is saved so you can resume later from that point
- **"LOGIN FOUND" notification** — a clear push notification is sent when a successful login is detected
- **Progress display** — shows current email index, current password round (1/2/3), and which platform each session is testing
- **Reuses existing automation engine, proxy infrastructure, stealth settings, and URL rotation** from the app

## Design

- **Main Menu** gets a new zone button styled similarly to the existing ones — uses a magnifying glass icon with a purple/violet gradient accent to distinguish it from the other modes
- **Setup screen** with a dark theme matching the app's existing look:
  - Segmented picker at the top for 4 or 6 sessions
  - Text editor area for pasting emails
  - 3 secure text fields for the passwords
  - Email count badge showing how many were parsed
  - "Start" button at the bottom
- **Running screen** shows:
  - A live progress bar (e.g. "Email 47/200 — Password 2/3")
  - Session cards for each active session showing site (Joe/Ignition), current email, status
  - Pause / Stop controls
  - A log feed at the bottom
- **Login Found alert** — a prominent banner or sheet with haptic feedback when a hit is detected, showing the email and password that worked
- **Resume banner** at the top of the setup screen if a previous run was interrupted, with a "Resume" button

## Screens

1. **Main Menu** — updated with a new "Dual Find" button in the layout
2. **Dual Find Setup** — email import area, 3 password fields, session count toggle, start button
3. **Dual Find Running** — live progress, session monitor, logs, pause/stop controls, login-found alert
