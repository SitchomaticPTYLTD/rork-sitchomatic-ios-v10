# Bulletproof DNS & Internet Connection with Test All & Auto-Disable

## Features

- **"Test All DNS" button** in the Network Settings DNS section — runs a latency test against every DNS provider simultaneously and shows results inline (latency, pass/fail status)
- **Auto-disable failing DNS providers** — any provider that fails the test or times out gets automatically disabled so it won't be used during checks
- **Pre-batch connectivity gate** — before starting any batch test, automatically runs a quick internet + DNS health check; if it fails, the batch is blocked with a clear message
- **Mid-batch connection watchdog** — monitors connectivity during batch runs; if multiple consecutive connection failures happen, auto-pauses the batch, runs diagnostics, and attempts recovery before resuming
- **Resilient DNS resolution** — increases retry attempts from 3 to 5, adds per-provider health tracking (fail counts), and automatically skips providers that have failed recently
- **Internet connectivity retry with backoff** — the internet check now tries more endpoints with exponential backoff before declaring failure
- **Auto-heal enhancements** — connection failures during batch runs now automatically disable bad DNS providers and switch to known-good ones

## Design

- DNS provider rows in Network Settings now show a latency badge (e.g. "142ms" in green, "FAIL" in red) after running "Test All"
- A new "Test All DNS" button at the top of the DNS section with a spinning indicator while testing
- Failed providers get a red "FAIL" badge and are auto-toggled off with an orange "Auto-disabled" label
- A subtle toast/log message appears when providers are auto-disabled during batch runs
- The batch progress card shows a small connectivity indicator (green dot = healthy, yellow = degraded, red = down)

## Changes

### DNS Service (PPSRDoHService)
- Add per-provider health tracking: fail count, last test latency, last test status
- Add `testAllProviders()` method — tests every managed provider in parallel, returns results, auto-disables failures
- Add `markProviderFailed()` / `markProviderHealthy()` to track reliability
- Skip providers with 3+ recent failures in `nextProvider()` rotation
- Increase rotation attempts from 3 to 5

### Connection Diagnostic Service
- Add `preflightGate()` — lightweight pre-batch check (internet + DNS + quick HTTP)
- Enhance `quickHealthCheck()` with retry logic and multiple fallback endpoints
- Add connectivity watchdog method for mid-batch monitoring

### Automation ViewModel
- Add pre-batch connectivity gate before `testAllUntested()` and `testSelectedCards()`
- Enhance mid-batch failure handling: auto-pause → diagnose → disable bad DNS → resume
- Add `dnsTestResults` property for UI to display test results
- Add `testAllDNS()` method that delegates to the service and updates UI
- Track batch connectivity health indicator

### Network Settings View
- Add "Test All DNS" button with progress indicator
- Show latency/status badge on each DNS provider row after test
- Show "Auto-disabled" label on providers that were turned off by the system
- Add "Re-enable All" quick action after test

### Automation Engine
- Enhance DoH preflight to skip known-bad providers
- Report DNS provider health back to the service after each use
