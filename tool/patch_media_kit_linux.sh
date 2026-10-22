#!/usr/bin/env bash
# Patch media_kit_video to build without mpv on Linux (ideal UX).
# Without this, `flutter run` on Arch without `sudo pacman -S mpv` fails with:
#   Target "media_kit_video_plugin" links to PkgConfig::mpv but not found.
# After patch, build succeeds with dummy plugin and Dart shows placeholder.
# For full inline video on Linux: sudo pacman -S mpv libepoxy

set -e
FILE="$HOME/.pub-cache/hosted/pub.dev/media_kit_video-1.3.1/linux/CMakeLists.txt"
if [ ! -f "$FILE" ]; then
  # try find any version
  FILE=$(find "$HOME/.pub-cache/hosted/pub.dev" -path "*media_kit_video*/linux/CMakeLists.txt" | head -n1)
fi
if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "media_kit_video CMakeLists not found, skip patch"
  exit 0
fi
if grep -q "mpv_FOUND AND epoxy_FOUND" "$FILE"; then
  echo "media_kit_video already patched"
  exit 0
fi
echo "Patching $FILE for mpv-optional build..."

cat > "$FILE" << 'EOF'
# This file is a part of media_kit (https://github.com/media-kit/media-kit).
#
# Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
# All rights reserved.
# Use of this source code is governed by MIT license that can be found in the LICENSE file.

cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "media_kit_video")
set(CMAKE_CXX_STANDARD 17)
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "media_kit_video_plugin")

if(MEDIA_KIT_LIBS_AVAILABLE)
  find_package(PkgConfig REQUIRED)
  pkg_check_modules(mpv IMPORTED_TARGET mpv)
  pkg_check_modules(epoxy IMPORTED_TARGET epoxy)

  if(mpv_FOUND AND epoxy_FOUND)
    add_library(
      ${PLUGIN_NAME} SHARED
      "media_kit_video_plugin.cc"
      "texture_gl.cc"
      "texture_sw.cc"
      "video_output_manager.cc"
      "video_output.cc"
      "utils.cc"
    )
    apply_standard_settings(${PLUGIN_NAME})
    set_target_properties(
      ${PLUGIN_NAME} PROPERTIES
      CXX_VISIBILITY_PRESET hidden
    )
    target_compile_definitions(
      ${PLUGIN_NAME} PRIVATE
      FLUTTER_PLUGIN_IMPL
    )
    target_compile_options(${PLUGIN_NAME} PRIVATE "${mpv_CFLAGS_OTHER}")
    target_compile_options(${PLUGIN_NAME} PRIVATE "${epoxy_CFLAGS_OTHER}")
    target_include_directories(
      ${PLUGIN_NAME} INTERFACE
      "${CMAKE_CURRENT_SOURCE_DIR}/include"
      "${mpv_INCLUDE_DIRS}"
      "${epoxy_INCLUDE_DIRS}"
    )
    target_link_libraries(
      ${PLUGIN_NAME} PRIVATE
      flutter
      PkgConfig::GTK
      PkgConfig::mpv
      PkgConfig::epoxy
    )
  else()
    message(WARNING "media_kit: mpv or epoxy not found (mpv_FOUND=${mpv_FOUND} epoxy_FOUND=${epoxy_FOUND}) - building dummy plugin without video support. Install mpv: sudo pacman -S mpv libepoxy for full Linux video support.")
    add_library(
      ${PLUGIN_NAME} SHARED
      "media_kit_video_plugin.cc"
    )
    apply_standard_settings(${PLUGIN_NAME})
    set_target_properties(
      ${PLUGIN_NAME} PROPERTIES
      CXX_VISIBILITY_PRESET hidden
    )
    target_compile_definitions(
      ${PLUGIN_NAME} PRIVATE
      FLUTTER_PLUGIN_IMPL
      "MEDIA_KIT_LIBS_NOT_FOUND=1"
    )
    target_include_directories(
      ${PLUGIN_NAME} INTERFACE
      "${CMAKE_CURRENT_SOURCE_DIR}/include"
    )
    target_link_libraries(
      ${PLUGIN_NAME} PRIVATE
      flutter
      PkgConfig::GTK
    )
  endif()
else()
  message(NOTICE "media_kit: WARNING: package:media_kit_libs_*** not found.")

  add_library(
    ${PLUGIN_NAME} SHARED
    "media_kit_video_plugin.cc"
  )

  apply_standard_settings(${PLUGIN_NAME})

  set_target_properties(
    ${PLUGIN_NAME} PROPERTIES
    CXX_VISIBILITY_PRESET hidden
  )

  target_compile_definitions(
    ${PLUGIN_NAME} PRIVATE
    FLUTTER_PLUGIN_IMPL

    # Add macro to indicate that package:media_kit_libs_*** is not available.
    "MEDIA_KIT_LIBS_NOT_FOUND=1"
  )

  target_include_directories(
    ${PLUGIN_NAME} INTERFACE
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
  )

  target_link_libraries(
    ${PLUGIN_NAME} PRIVATE
    flutter
    PkgConfig::GTK
  )
endif()

set(
  media_kit_video_bundled_libraries
  ""
  PARENT_SCOPE
)
EOF
echo "Patched $FILE"
