# Changelog

## Unreleased

### Fixed
- **Sidecar Process Termination on CMD+Q**: Fixed an issue where pressing CMD+Q (or other app-level quit commands) would not properly terminate the sidecar process, leaving it running in the background. The fix adds a `RunEvent::ExitRequested` handler that explicitly kills the sidecar before the application exits. This ensures proper cleanup whether the user closes the window via the close button or uses CMD+Q/Alt+F4.

### Technical Details
The fix implements:
1. A reusable `kill_sidecar()` function to avoid code duplication
2. Window close event handling (existing behavior, now using the helper function)
3. App-level exit event handling via `RunEvent::ExitRequested` (new)
4. A brief cleanup delay (100ms) to ensure the sidecar process is fully terminated before app exit

This change affects both the example application and the template generator, so all new ExTauri projects will include this fix.
