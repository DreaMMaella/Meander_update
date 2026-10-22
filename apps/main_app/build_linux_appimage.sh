#!/bin/bash
set -e

echo "==> Убеждаемся, что Flutter собран под Linux Release..."
flutter build linux --release

echo "==> Копируем нативное Rust-ядро (libmnd_ffi.so) в бандл..."
if [ ! -f "target/release/libmnd_ffi.so" ] && [ ! -f "../../target/release/libmnd_ffi.so" ]; then
    echo "Ошибка: libmnd_ffi.so не найдена. Сначала собери её: ./scripts/build_ffi.sh" >&2
    exit 1
fi
if [ -f "target/release/libmnd_ffi.so" ]; then
    cp target/release/libmnd_ffi.so build/linux/x64/release/bundle/lib/
else
    cp ../../target/release/libmnd_ffi.so build/linux/x64/release/bundle/lib/
fi

echo "==> Подготавливаем файловую структуру AppDir..."
rm -rf AppDir
mkdir -p AppDir
cp -r build/linux/x64/release/bundle/* AppDir/

echo "==> Создаем AppRun (скрипт запуска)..."
cat > AppDir/AppRun <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/canvas_app" "$@"
EOF
chmod +x AppDir/AppRun

echo "==> Создаем .desktop файл..."
cat > AppDir/canvas_app.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Meander
Comment=Interactive quest editor and player
Exec=canvas_app
Icon=canvas_app
Terminal=false
Categories=Development;Game;
EOF

echo "==> Копируем иконку..."
# Если иконка находится в другом месте локально, поправьте путь
if [ -f "assets/icon/icon.png" ]; then
    cp assets/icon/icon.png AppDir/canvas_app.png
elif [ -f "assets/images/logo.png" ]; then
    cp assets/images/logo.png AppDir/canvas_app.png
else
    # Создаем заглушку, если иконка не найдена (AppImageTool требует иконку)
    touch AppDir/canvas_app.png
    echo "Внимание: Иконка приложения не найдена, создана пустая заглушка."
fi

echo "==> Скачиваем appimagetool..."
if [ ! -f "appimagetool-x86_64.AppImage" ]; then
    wget -q https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
    chmod +x appimagetool-x86_64.AppImage
fi

echo "==> Собираем Meander.AppImage..."
APPIMAGE_EXTRACT_AND_RUN=1 ARCH=x86_64 ./appimagetool-x86_64.AppImage AppDir Meander-linux-x64.AppImage

echo "==> Готово! Ваш универсальный файл: Meander-linux-x64.AppImage"
echo "Очистка временной папки AppDir..."
rm -rf AppDir
