#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
configuration="${1:-release}"
if [[ "$configuration" != "release" && "$configuration" != "debug" ]]; then
    echo "Usage: $0 [release|debug] [output.app]" >&2
    exit 2
fi

swift_options=(--configuration "$configuration" --manifest-cache none)
swift build "${swift_options[@]}" --product OpenWilo
binary_dir="$(swift build "${swift_options[@]}" --show-bin-path)"
app="${2:-$PWD/dist/OpenWilo.app}"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
install -m 755 "$binary_dir/OpenWilo" "$app/Contents/MacOS/OpenWilo"
install -m 644 Resources/Info.plist "$app/Contents/Info.plist"
install -m 644 Resources/OpenWilo.icns "$app/Contents/Resources/OpenWilo.icns"
install -m 644 LICENSE "$app/Contents/Resources/LICENSE"
/usr/bin/codesign --force --sign - "$app"
/usr/bin/codesign --verify --strict "$app"
printf '%s\n' "$app"
