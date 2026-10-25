# arc-shell — la shell grafica di arc UI (topbar, dock, widget, launcher,
# notifiche) che sostituisce plasmashell sopra KWin.
cmake_minimum_required(VERSION 3.22)
project(arc-shell VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(ECM 6.0 REQUIRED NO_MODULE)
list(APPEND CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
include(KDEInstallDirs)

find_package(Qt6 6.6 REQUIRED COMPONENTS Core Gui DBus Qml Quick)
find_package(KF6 6.0 REQUIRED COMPONENTS Service KIO WindowSystem Runner)
find_package(LayerShellQt 6.0 REQUIRED)

add_executable(arc-shell
    src/main.cpp
    src/shell.cpp
    src/applications.cpp
    src/notifications.cpp
    src/media.cpp
    src/osd.cpp
    src/search.cpp
)

file(GLOB ARC_QML_FILES RELATIVE ${CMAKE_CURRENT_SOURCE_DIR}
    qml/*.qml qml/qmldir qml/assets/*)
qt_add_resources(arc-shell "arc-qml" PREFIX "/" FILES ${ARC_QML_FILES})

target_link_libraries(arc-shell PRIVATE
    Qt6::Core Qt6::Gui Qt6::DBus Qt6::Qml Qt6::Quick
    KF6::Service KF6::KIOGui KF6::WindowSystem KF6::Runner
    LayerShellQt::Interface)

install(TARGETS arc-shell DESTINATION ${KDE_INSTALL_BINDIR})
