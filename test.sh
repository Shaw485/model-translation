#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/module-cache
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path build/module-cache Sources/Core.swift Tests/CoreTests.swift -o build/CoreTests
./build/CoreTests
