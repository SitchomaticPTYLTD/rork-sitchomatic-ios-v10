# Complete A-Z Code Audit — Fix All Build Errors & Warnings

## Issues Found & Fixes

### 1. ExportHistoryService — Missing Methods & Properties

The `ExportHistoryService` class is empty but referenced throughout the app for `records`, `recordExport()`, and `clearHistory()`.

**Fix:** Add the missing `ExportRecord` struct, `records` array, `recordExport()`, and `clearHistory()` methods with persistence.

---

### 2. TestSchedule — Missing `isActive` Property

`PPSRSettingsView` references `schedule.isActive` but it doesn't exist on `TestSchedule`.

**Fix:** Add a computed `isActive` property that returns `true` if the scheduled date is in the future.

---

### 3. LoginWebSession — Concurrency Warning (becomes error in Swift 6)

The `decidePolicyFor navigationResponse` delegate method has two problems:

- Accesses `navigationResponse.response` (a main-actor-isolated property) from a `nonisolated` context — causes repeated warnings
- Calls `completion(false, ...)` for every response, which can prematurely mark navigation as failed before `didFinish` fires — this is a logic bug

**Fix:** Rewrite the delegate method to extract the HTTP status code safely and store it without calling completion. Add a `lastStatusCode` property to the delegate and read it from the session.

---

### 4. GreenBannerDetector — Unused Variable Warning

`bestEnd` is written to but never read.

**Fix:** Remove the unused `bestEnd` variable since `bestStart` and `bestLength` are sufficient.

---

### 5. ProxyRotationService — Captured Var in Concurrent Code

`lastErrorDesc` is a mutable `var` referenced inside a concurrent `Task` closure, which is a Swift 6 error.

**Fix:** Copy `lastErrorDesc` to a `let` constant before using it inside the `Task` block (already partially done but needs cleanup).

---

### Summary

