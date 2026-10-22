# Project-level configuration.
cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "canvas_app")
# The unique GTK application identifier for this application. See:
# https://wiki.gnome.org/HowDoI/ChooseApplicationID
set(APPLICATION_ID "com.IILLUMINAT.meadner")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(SET CMP0063 NEW)

# Load bundled libraries from the lib/ directory relative to the binary.
set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# Root filesystem for cross-building.
if(FLUTTER_TARGET_PLATFORM_SYSROOT)
  set(CMAKE_SYSROOT ${FLUTTER_TARGET_PLATFORM_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH ${CMAKE_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
  set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
endif()

# Define build configuration options.
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE "Debug" CACHE
    STRING "Flutter build mode" FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
    "Debug" "Profile" "Release")
endif()

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_14)
  target_compile_options(${TARGET} PRIVATE -Wall)
  target_compile_options(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")
  target_compile_definitions(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:NDEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# System-level dependencies.
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# === Rust FFI (mnd-ffi) auto-build ===
# FRB-лоадер грузит libmnd_ffi.so напрямую из crates/mnd-ffi/target/release/
# (frb_generated.dart → ioDirectory), поэтому `flutter run` сам по себе
# Rust НЕ пересобирает. Дергаем cargo при каждой сборке: если исходники
# свежее артефакта — пересборка, иначе no-op (~0.1 c).
find_program(CARGO_EXECUTABLE cargo PATHS "$ENV{HOME}/.cargo/bin")
if(CARGO_EXECUTABLE)
  add_custom_target(cargo_build_mnd_ffi
    COMMAND ${CARGO_EXECUTABLE} build --release -p mnd-ffi
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../.."
    BYPRODUCTS "${CMAKE_CURRENT_SOURCE_DIR}/../../target/release/libmnd_ffi.so"
    COMMENT "cargo build --release -p mnd-ffi"
    VERBATIM
  )
  add_dependencies(${BINARY_NAME} cargo_build_mnd_ffi)
else()
  message(WARNING "cargo не найден — libmnd_ffi.so не будет пересобран; "
    "соберите вручную: cargo build --release -p mnd-ffi")
endif()

# Only the install-generated bundle's copy of the executable will launch
# correctly, since the resources must in the right relative locations. To avoid
# people trying to run the unbundled copy, put it in a subdirectory instead of
# the default top-level location.
set_target_properties(${BINARY_NAME}
  PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/intermediates_do_not_run"
)


# --- media_kit Linux video handling (ideal UX without extra deps) ---
# media_kit_video на Linux требует mpv + libepoxy (pkg-config mpv); на
# Windows/macOS/Android/iOS библиотеки приходят из media_kit_libs_*. Чтобы
# сборка жила и без mpv, здесь же и выключаем MEDIA_KIT_LIBS_AVAILABLE: у
# самого плагина на этот случай встроен dummy-плагин с определением
# MEDIA_KIT_LIBS_NOT_FOUND, а Dart (_isLinuxMpAvailable) рисует заглушку.
# Раньше для этого руками латали копию пакета в ~/.pub-cache — латка не переживала
# перевыгрузку пакета и не была в репозитории.
# Для инлайн-плеера на dev-машине: sudo pacman -S mpv libepoxy
# Для релизной упаковки через AUR: добавить mpv в Depends в PKGBUILD.
find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
  pkg_check_modules(MPV_CHECK QUIET IMPORTED_TARGET mpv)
  pkg_check_modules(EPOXY_CHECK QUIET IMPORTED_TARGET epoxy)
  if(NOT MPV_CHECK_FOUND OR NOT EPOXY_CHECK_FOUND)
    message(WARNING "mpv/libepoxy не найдены - Linux видео соберётся dummy-плагином (поставьте mpv для инлайн-плеера)")
    set(MEDIA_KIT_LIBS_AVAILABLE OFF CACHE BOOL "package:media_kit libraries are available." FORCE)
  endif()
endif()

# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# By default, "installing" just makes a relocatable bundle in the build
# directory.
set(BUILD_BUNDLE_DIR "${PROJECT_BINARY_DIR}/bundle")
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

# Start with a clean build bundle directory every time.
install(CODE "
  file(REMOVE_RECURSE \"${BUILD_BUNDLE_DIR}/\")
  " COMPONENT Runtime)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

foreach(bundled_library ${PLUGIN_BUNDLED_LIBRARIES})
  install(FILES "${bundled_library}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endforeach(bundled_library)

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/linux/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")
  install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Desktop integration for ".mnd" files.
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/runner/meander.desktop"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/share/applications"
  COMPONENT Runtime)
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/runner/meander-mnd.xml"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/share/mime/packages"
  COMPONENT Runtime)
# Тема значков (hicolor): её ищет и .desktop (Icon=meander), и GTK-окно.
install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/runner/icons/"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/share/icons"
  COMPONENT Runtime)
