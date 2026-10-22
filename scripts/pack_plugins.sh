#!/usr/bin/env bash
# Сборка эталонных плагинов в архивы для установки в приложение.
#
# Плагин — это папка с plugin.json и Lua: в zip кладётся ровно она, без
# мусора и без лишних уровней. Экран «Плагины» принимает такой архив как есть
# (ищет plugin.json, берёт каталог вокруг него как корень пакета).
#
# Использование:
#   ./scripts/pack_plugins.sh                 # все плагины из plugins/examples
#   ./scripts/pack_plugins.sh status-hud shop # только перечисленные
#   PLUGIN_SRC=plugins/my-plugins ./scripts/pack_plugins.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$(cd "$REPO_ROOT" && realpath -m "${PLUGIN_SRC:-plugins/examples}")"
OUT_DIR="$(cd "$REPO_ROOT" && mkdir -p "${PLUGIN_DIST:-plugins/dist}" && realpath "${PLUGIN_DIST:-plugins/dist}")"

if [[ ! -d "$SRC_DIR" ]]; then
    echo "Каталог плагинов не найден: $SRC_DIR" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR"/*.zip

packed=0
for dir in "$SRC_DIR"/*/; do
    name="$(basename "$dir")"
    if [[ $# -gt 0 && ! " $* " == *" $name "* ]]; then
        continue
    fi
    manifest="$dir/plugin.json"
    if [[ ! -f "$manifest" ]]; then
        echo "⏭  $name: нет plugin.json — пропускаем"
        continue
    fi

    # Имя архива берём из манифеста, а не из папки: id и version — то, что
    # видит пользователь при импорте.
    read -r id version < <(python3 - "$manifest" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    manifest = json.load(handle)
print(manifest["id"], manifest.get("version", "0"))
PY
)
    if [[ -z "$id" ]]; then
        echo "⏭  $name: в манифесте нет id — пропускаем"
        continue
    fi

    target="$OUT_DIR/${id}-${version}.zip"
    rm -f "$target"
    # -r из каталога-родителя: в архиве путь начинается с $name/.
    (cd "$(dirname "$dir")" && zip --quiet -r "$target" "$name" -x '*.DS_Store')
    echo "✅ $name → $(basename "$target") ($(du -h "$target" | cut -f1))"
    packed=$((packed + 1))
done

if [[ $packed -eq 0 ]]; then
    echo "Нечего паковать: в $SRC_DIR нет плагинов с plugin.json" >&2
    exit 1
fi

echo
echo "Дальше: перенести архив на устройство и «Плагины» → «Импортировать плагин»."
