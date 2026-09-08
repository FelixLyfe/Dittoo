#!/bin/bash
# Pure Swift harnesses for the clipboard-only Dittoo source set.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

BIN="${TMPDIR:-/tmp}/Dittoo-harness"
mkdir -p "$BIN"

failed=()
ran=0
only="${1:-}"
emit_db=0
DB="${TMPDIR:-/tmp}/Dittoo-compile-db.json"
if [ "$only" = "--index" ]; then
    emit_db=1
    only=""
    printf '[' > "$DB"
fi

run() {
    local name=$1
    shift
    if [ -n "$only" ] && [ "$name" != "$only" ]; then return 0; fi
    ran=$((ran + 1))

    if [ "$emit_db" -eq 1 ]; then
        local sources=()
        for source in "$@" "Tests/$name.swift"; do
            if [[ "$source" != -* ]]; then sources+=("$PWD/$source"); fi
        done
        [ "$ran" -gt 1 ] && printf ',' >> "$DB"
        printf '{"directory":"%s","command":"swiftc -swift-version 6 -sdk %s' \
            "$PWD" "$(xcrun --show-sdk-path --sdk macosx)" >> "$DB"
        printf ' %s' "${sources[@]}" >> "$DB"
        printf '","files":["%s/Tests/%s.swift"]}' "$PWD" "$name" >> "$DB"
        return 0
    fi

    if ! swiftc -swift-version 6 "$@" "Tests/$name.swift" -o "$BIN/$name" 2>&1; then
        printf '\033[31mFAIL\033[0m  %-22s did not compile\n' "$name"
        failed+=("$name")
        return 0
    fi
    if ! "$BIN/$name"; then
        printf '\033[31mFAIL\033[0m  %-22s assertion failed\n' "$name"
        failed+=("$name")
        return 0
    fi
    printf '\033[32mok\033[0m    %-22s\n' "$name"
}

run clipboard-test -lsqlite3 \
    Dittoo/Platform/AppPaths.swift \
    Dittoo/Features/Clipboard/Model/ClipboardStore.swift \
    Dittoo/Features/Clipboard/Model/ClipboardFilter.swift
run clipboard-reliability-test -lsqlite3 \
    Dittoo/Platform/AppPaths.swift \
    Dittoo/Features/Clipboard/Model/ClipboardStore.swift \
    Dittoo/Features/Clipboard/Model/ClipboardFilter.swift
run activation-policy-test Dittoo/Platform/ActivationPolicy.swift
run paster-test -lsqlite3 \
    Dittoo/Platform/AppPaths.swift \
    Dittoo/Features/Clipboard/Model/ClipboardStore.swift \
    Dittoo/Features/Clipboard/Model/ClipboardFilter.swift \
    Dittoo/Features/Clipboard/Service/Paster.swift
run appearance-test \
    Dittoo/Platform/Appearance.swift \
    Dittoo/DesignSystem/Theme.swift \
    Dittoo/Features/Settings/AppAppearance.swift
run palette-placement-test \
    Dittoo/Platform/Appearance.swift \
    Dittoo/DesignSystem/Theme.swift \
    Dittoo/Palette/PalettePlacement.swift
run scroll-reveal-test Dittoo/DesignSystem/Scrolling/SelectionReveal.swift
run hover-arming-test \
    Dittoo/Palette/HoverArming.swift \
    Dittoo/Palette/PaletteState.swift \
    Dittoo/Palette/PaletteMode.swift \
    Dittoo/Features/Clipboard/Model/ClipboardStore.swift \
    Dittoo/Features/Clipboard/Model/ClipboardFilter.swift \
    Dittoo/Platform/AppPaths.swift -lsqlite3
run hotkey-test \
    Dittoo/Features/HotKeys/Service/KeyShortcut.swift \
    Dittoo/Features/HotKeys/Model/HotKeyBinding.swift \
    Dittoo/Features/HotKeys/Model/HotKeyAction.swift
run callout-test \
    Dittoo/Platform/Appearance.swift \
    Dittoo/DesignSystem/Theme.swift \
    Dittoo/Features/HotKeys/UI/CalloutPlacement.swift
run menu-bar-icon-test -parse-as-library
run icon-cache-test \
    Dittoo/Platform/Appearance.swift \
    Dittoo/Platform/Images/IconCache.swift
run settings-history-test \
    Dittoo/Features/Settings/SettingsTab.swift \
    Dittoo/Features/Settings/SettingsHistory.swift

if [ "$emit_db" -eq 1 ]; then
    printf ']\n' >> "$DB"
    [ -f .compile ] || echo '[]' > .compile
    python3 - .compile "$DB" <<'PY'
import json, sys

compile_path, harness_path = sys.argv[1], sys.argv[2]
existing = json.load(open(compile_path))
harnesses = json.load(open(harness_path))
kept = [e for e in existing if not any("/Tests/" in f for f in e.get("files") or [])]
json.dump(kept + harnesses, open(compile_path, "w"), indent=1)
print(f"{len(harnesses)} harness entries indexed into .compile")
PY
    exit 0
fi

if [ "$ran" -eq 0 ]; then
    echo "No harness named '$only'." >&2
    exit 2
fi
if [ ${#failed[@]} -gt 0 ]; then
    printf '\n%d harness(es) failed: %s\n' "${#failed[@]}" "${failed[*]}" >&2
    exit 1
fi
echo
if [ -n "$only" ]; then echo "$only passed."; else echo "All $ran harnesses passed."; fi
