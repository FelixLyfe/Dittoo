# Engineering standards

- Target the current macOS and Swift toolchain; do not add compatibility layers.
- Keep `AppCore` as the sole owner of long-lived services.
- Keep model code pure and cross-actor values `Sendable`.
- Move expensive image or database preparation off the main actor.
- Use Application Support for user data and bundle-scoped defaults for preferences.
- Add no third-party dependencies, network calls, analytics, or telemetry.
- Keep comments short and focused on invariants or non-obvious reasons.
- Preserve complete English and Simplified Chinese localizations.
- Regenerate the Xcode project after source-tree or `project.yml` changes.
