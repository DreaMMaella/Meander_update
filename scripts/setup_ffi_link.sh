#!/usr/bin/env bash
# Настраивает симлинк crates/mnd-ffi/target -> ../../target.
#
# flutter_rust_bridge ожидает нативную библиотеку в
# `crates/mnd-ffi/target/release/`, а cargo workspace собирает её в корневой
# `target/release/`. Симлинк выравнивает оба пути на один физический файл —
# без копирования и без рассинхрона content hash.
#
# Идемпотентен: если это уже симлинк (или папка-мираж), приводит к нужному виду.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_LINK="$REPO_ROOT/crates/mnd-ffi/target"

if [[ -L "$TARGET_LINK" ]]; then
    # Уже симлинк — ничего не делаем.
    exit 0
fi

# Реальная папка (сиротская копия) — удаляем и делаем симлинк.
rm -rf "$TARGET_LINK"
ln -s ../../target "$TARGET_LINK"
echo "создан симлинк $TARGET_LINK -> ../../target"
