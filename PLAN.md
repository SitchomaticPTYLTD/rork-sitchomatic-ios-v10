# Fix app installation failure on simulator

The app builds successfully but fails to install on the simulator. This is likely caused by stale build artifacts or a minor configuration mismatch from previous widget extension cleanup attempts.

**Changes:**
- Bump the app's internal build version number to force a clean reinstall on the simulator
- Fix the test scheme references that have incorrect target names (cosmetic but can confuse the build system)
- Ensure the project configuration is fully clean with no leftover references
