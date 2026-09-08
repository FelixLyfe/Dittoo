# Architecture

`AppCore` is the composition root. It owns settings, the SQLite clipboard store, clipboard polling,
the global hotkey, the palette state, and window coordinators.

`ClipboardManager` polls `NSPasteboard`, rejects sensitive markers and excluded source apps, and
writes text or PNG data to `ClipboardStore`. The store persists rows and image files in the current
bundle's Application Support directory. Debug and Release bundle IDs therefore remain isolated.

`PaletteWindowController` hosts the single clipboard browser. `ClipboardCoordinator` owns user
actions, while `Paster` writes an internal pasteboard marker and synthesizes Command-V only after an
actual paste requests Accessibility trust.

Onboarding does not start polling until the user presses Done.
