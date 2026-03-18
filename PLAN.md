# Fix App Installation Failure

The "App installation failed" error (with no additional details) typically means the built app bundle has a structural issue the simulator rejects. Based on my investigation, the most likely cause is the widget extension configuration.

**What will be fixed:**

- **Remove the widget extension target entirely** — The widget only contains a Live Activity widget, which the cloud simulator cannot display anyway. Removing it eliminates the recurring source of build/install failures (this is the 4th time this target has caused issues)
- **Keep all Live Activity code in the main app** — The `PPSRActivityAttributes` model and `PPSRLiveActivityService` in the main app remain untouched, so Live Activities still work when installed on a real device
- **Clean up the project file** — Remove the widget target, its build phases, dependencies, and embed phase from the Xcode project configuration

This is the safest fix since the widget target has been the root cause of multiple consecutive failures.
