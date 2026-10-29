#!/bin/zsh
# 커서 계산 로직 테스트 (앱 없이 실행)
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
swiftc -swift-version 5 -o build/tests Sources/PointerMath.swift Tests/main.swift
./build/tests
