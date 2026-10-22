#!/usr/bin/env bash
# Сборка нативной библиотеки mnd-ffi (.so) и регенерация Dart-биндингов.
#
# Как устроено:
#   cargo workspace собирает артефакты в корневой `target/release/`, а
#   flutter_rust_bridge генерирует `ioDirectory: ../../crates/mnd-ffi/target/release/`
#   (ждёт библиотеку в `crates/mnd-ffi/target/`). Чтобы оба пути указывали на
#   один физический файл, `crates/mnd-ffi/target` — это симлинк на корневой
#   `target/` (см. `scripts/setup_ffi_link.sh`). Поэтому обычная сборка
#   `cargo build --release -p mnd-ffi` сразу кладёт `.so` туда, откуда грузит Flutter.
#
# Использование: ./scripts/build_ffi.sh [--no-codegen]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Убеждаемся, что симлинк на месте (идемпотентно).
if ! "$REPO_ROOT/scripts/setup_ffi_link.sh"; then
    echo "Ошибка: не удалось настроить симлинк crates/mnd-ffi/target -> target" >&2
    exit 1
fi

echo "==> cargo build --release -p mnd-ffi (Host Linux/Desktop)"
cargo build --release -p mnd-ffi

echo "==> cargo ndk build --release -p mnd-ffi (Android: arm64-v8a, armeabi-v7a, x86, x86_64)"
cargo ndk --platform 24 -t arm64-v8a -t armeabi-v7a -t x86 -t x86_64 -o apps/main_app/android/app/src/main/jniLibs build --release -p mnd-ffi

if [[ "${1:-}" != "--no-codegen" ]]; then
    echo "==> flutter_rust_bridge_codegen generate"
    flutter_rust_bridge_codegen generate
fi

echo "==> готово. Перезапусти flutter run (не hot-reload) чтобы подхватить .so"
