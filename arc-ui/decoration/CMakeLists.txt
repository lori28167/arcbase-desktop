# arc — decorazione delle finestre di arc UI per KWin (KDecoration3):
# barra del titolo di vetro sfocato, nome dell'app a sinistra, pulsanti tondi
# scuri a destra (riduci, ingrandisci, chiudi), angoli arrotondati.
cmake_minimum_required(VERSION 3.22)
project(arc-decoration VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(ECM 6.0 REQUIRED NO_MODULE)
list(APPEND CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
include(KDEInstallDirs)

find_package(Qt6 6.6 REQUIRED COMPONENTS Core Gui)
find_package(KF6 6.0 REQUIRED COMPONENTS CoreAddons)
find_package(KDecoration3 REQUIRED)

add_library(arcdecoration MODULE arcdecoration.cpp)
set_target_properties(arcdecoration PROPERTIES OUTPUT_NAME org.arcbase.arc PREFIX "")
target_link_libraries(arcdecoration PRIVATE Qt6::Core Qt6::Gui KF6::CoreAddons KDecoration3::KDecoration)

install(TARGETS arcdecoration DESTINATION ${KDE_INSTALL_PLUGINDIR}/${KDECORATION_PLUGIN_DIR})
