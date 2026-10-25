# Modulo "Sfondo" di Impostazioni di sistema per arc (sotto Aspetto).
# Parla con arc-shell su D-Bus (org.arcbase.Shell): elenco, scelta, aggiunta.
cmake_minimum_required(VERSION 3.22)
project(kcm_arcwallpaper LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(ECM 6.0 REQUIRED NO_MODULE)
list(APPEND CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
include(KDEInstallDirs)
include(KDECMakeSettings)

find_package(Qt6 6.6 REQUIRED COMPONENTS Core DBus Qml Quick)
find_package(KF6 6.0 REQUIRED COMPONENTS KCMUtils CoreAddons)

kcmutils_add_qml_kcm(kcm_arcwallpaper SOURCES wallpapermodule.cpp wallpapermodule.h)
target_link_libraries(kcm_arcwallpaper PRIVATE Qt6::DBus Qt6::Quick KF6::KCMUtilsQuick KF6::CoreAddons)
