cmake_minimum_required(VERSION 3.20)

project(libarc_support VERSION 1.1.1 LANGUAGES C OBJC)

set(LIBARC_SUPPORT_SOURCES
    src/arc_alloc.m
    src/arc_bridge.m
    src/arc_core.m
    src/arc_pool.m
    src/arc_weak_runtime.m
    src/arc_weak_table.m)

set(LIBARC_SUPPORT_BLOCKS_SOURCES
    vendor/BlocksRuntime/data.c
    vendor/BlocksRuntime/runtime.c)

function(libarc_support_configure target)
    target_sources(${target} PRIVATE ${LIBARC_SUPPORT_SOURCES})
    target_include_directories(${target}
        PUBLIC
            "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>"
            "$<INSTALL_INTERFACE:include>"
        PRIVATE
            "${CMAKE_CURRENT_SOURCE_DIR}/private"
            "${CMAKE_CURRENT_SOURCE_DIR}/vendor/BlocksRuntime")
    target_compile_options(${target} PRIVATE
        $<$<COMPILE_LANGUAGE:OBJC>:-fno-objc-arc>)
    target_link_libraries(${target} PUBLIC
        "-framework CoreFoundation"
        "-framework Foundation"
        "-lobjc")
    set_target_properties(${target} PROPERTIES
        C_STANDARD 99
        C_STANDARD_REQUIRED YES
        C_EXTENSIONS YES)
endfunction()

function(libarc_support_add_blocks_runtime target)
    target_sources(${target} PRIVATE ${LIBARC_SUPPORT_BLOCKS_SOURCES})
endfunction()

add_library(arc_support_static STATIC)
libarc_support_configure(arc_support_static)
set_target_properties(arc_support_static PROPERTIES OUTPUT_NAME arc_support)
add_library(libarc_support::static ALIAS arc_support_static)

add_library(arc_support_legacy_static STATIC)
libarc_support_configure(arc_support_legacy_static)
libarc_support_add_blocks_runtime(arc_support_legacy_static)
set_target_properties(arc_support_legacy_static PROPERTIES
    OUTPUT_NAME arc_support_legacy)
add_library(libarc_support::legacy_static ALIAS arc_support_legacy_static)

add_library(arc_support SHARED)
libarc_support_configure(arc_support)
target_link_options(arc_support PRIVATE
    "-Wl,-exported_symbols_list,${CMAKE_CURRENT_SOURCE_DIR}/exports/libarc_support.exp"
    "-Wl,-current_version,1.1.1"
    "-Wl,-compatibility_version,1.0.0")
set_target_properties(arc_support PROPERTIES
    OUTPUT_NAME arc_support
    BUILD_WITH_INSTALL_NAME_DIR YES
    INSTALL_NAME_DIR ""
    MACOSX_RPATH OFF
    LINK_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/exports/libarc_support.exp")
add_library(libarc_support::dynamic ALIAS arc_support)

add_library(arc_support_legacy SHARED)
libarc_support_configure(arc_support_legacy)
libarc_support_add_blocks_runtime(arc_support_legacy)
target_link_options(arc_support_legacy PRIVATE
    "-Wl,-exported_symbols_list,${CMAKE_CURRENT_SOURCE_DIR}/exports/libarc_support-legacy.exp"
    "-Wl,-current_version,1.1.1"
    "-Wl,-compatibility_version,1.0.0")
set_target_properties(arc_support_legacy PROPERTIES
    OUTPUT_NAME arc_support_legacy
    BUILD_WITH_INSTALL_NAME_DIR YES
    INSTALL_NAME_DIR ""
    MACOSX_RPATH OFF
    LINK_DEPENDS
        "${CMAKE_CURRENT_SOURCE_DIR}/exports/libarc_support-legacy.exp")
add_library(libarc_support::legacy_dynamic ALIAS arc_support_legacy)

include(GNUInstallDirs)
install(TARGETS arc_support_static arc_support arc_support_legacy_static
        arc_support_legacy
    ARCHIVE DESTINATION "${CMAKE_INSTALL_LIBDIR}"
    LIBRARY DESTINATION "${CMAKE_INSTALL_LIBDIR}")
install(FILES
    include/libarc_support/arc_runtime.h
    vendor/BlocksRuntime/Block.h
    DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}/libarc_support")
install(FILES LICENSE THIRD-PARTY
    DESTINATION "${CMAKE_INSTALL_DATAROOTDIR}/licenses/libarc_support")
install(FILES vendor/BlocksRuntime/LICENSE
    DESTINATION "${CMAKE_INSTALL_DATAROOTDIR}/licenses/libarc_support/BlocksRuntime")
install(FILES vendor/PLWeakCompatibility/LICENSE
    DESTINATION "${CMAKE_INSTALL_DATAROOTDIR}/licenses/libarc_support/PLWeakCompatibility")
