# Clipboard history

Dittoo stores text up to 32,000 characters and PNG image data. Sensitive pasteboard markers and
copies from excluded bundle IDs are ignored. The list supports full-text search, text/image/link/email
filters, pinning, source-app metadata, removal, and retention pruning.

Internal copy and paste writes carry `io.github.felixlyfe.Dittoo.internal`, so polling does not
recapture them. Pinned rows are exempt from age pruning. Clear History removes rows and owned image
files after confirmation.

History queries read the database, including one- and two-character searches and image filters.
The browser loads 200 unpinned matches at a time, applying the type filter before the page limit;
scrolling or moving the keyboard selection past the last row loads more. All matching pins remain
visible above the paged history.

Database failures preserve the original files and show a persistent status in the clipboard browser
and Clipboard settings. Reload History retries opening and reading the store. Failed writes never
update the visible history or remove image files. Imports and recency changes use transactions, and
Clear History invalidates image conversions and writes that started before the clear.

Automatic paste checks the destination and Accessibility access before dismissing the browser,
then waits for activation and posts only to that process. Missing permission or a failed delivery
shows a copy-only fallback with manual-paste instructions. A clipboard change during the wait cancels
delivery. Ordinary windows keep the app in accessory mode without a Dock icon.

The store is SQLite-backed under Application Support. Image paths in the database always point to
files owned by the current Dittoo bundle channel.
