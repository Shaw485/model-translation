#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/module-cache CmdETranslate.app/Contents/MacOS CmdETranslate.app/Contents/Resources
xcrun swiftc -swift-version 5 -O -parse-as-library -target arm64-apple-macosx15.0 -module-cache-path build/module-cache Sources/*.swift -o CmdETranslate.app/Contents/MacOS/CmdETranslate
cp Info.plist CmdETranslate.app/Contents/Info.plist
xcrun swift -module-cache-path build/module-cache Icon.swift build/icon.png
mkdir -p build/AppIcon.iconset
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" build/icon.png --out "build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" build/icon.png --out "build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
python3 - <<'PY'
from pathlib import Path
import struct
chunks = []
for kind, size in [('icp4', 16), ('icp5', 32), ('icp6', 64), ('ic07', 128), ('ic08', 256), ('ic09', 512), ('ic10', 1024)]:
    filename = {64: 'icon_32x32@2x.png', 1024: 'icon_512x512@2x.png'}.get(size, f'icon_{size}x{size}.png')
    data = (Path('build/AppIcon.iconset') / filename).read_bytes()
    chunks.append(kind.encode('ascii') + struct.pack('>I', len(data) + 8) + data)
body = b''.join(chunks)
Path('CmdETranslate.app/Contents/Resources/AppIcon.icns').write_bytes(b'icns' + struct.pack('>I', len(body) + 8) + body)
PY
printf 'APPL????' > CmdETranslate.app/Contents/PkgInfo
codesign --force --sign - CmdETranslate.app
codesign --verify --deep --strict CmdETranslate.app
echo 'Built CmdETranslate.app'
