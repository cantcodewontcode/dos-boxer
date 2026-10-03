# DOS Boxer host library.
#
# Not a standalone project: dosbox-staging's CMakeLists.txt pulls this in when
# configured with -DDOSBOXER_HOST_DIR=<this dir> (see Scripts/build-core.sh).
# Produces libDOSBoxerCore.dylib, a self-contained emulator the app links.

# Everything the stock `dosbox` executable compiles directly (main.cpp,
# dosbox.cpp and a few files upstream attaches to the executable target)
get_target_property(DOSBOX_EXE_SOURCES dosbox SOURCES)
list(TRANSFORM DOSBOX_EXE_SOURCES PREPEND "${PROJECT_SOURCE_DIR}/" REGEX "^[^/]")

add_library(DOSBoxerCore SHARED
  ${CMAKE_CURRENT_LIST_DIR}/src/host_api.cpp
  ${CMAKE_CURRENT_LIST_DIR}/src/host_drives.cpp
  ${CMAKE_CURRENT_LIST_DIR}/src/host_renderer.cpp
  ${DOSBOX_EXE_SOURCES}
)

# Turn dosbox-staging's main() into a function we can call on our own thread
set_source_files_properties(${PROJECT_SOURCE_DIR}/src/main.cpp
  PROPERTIES COMPILE_DEFINITIONS "main=dosbox_staging_main"
)

target_include_directories(DOSBoxerCore
  PUBLIC  ${CMAKE_CURRENT_LIST_DIR}/include
  PRIVATE ${PROJECT_SOURCE_DIR}/include ${CMAKE_BINARY_DIR}/include
)

get_target_property(DOSBOX_EXE_LIBS dosbox LINK_LIBRARIES)

target_link_libraries(DOSBoxerCore PRIVATE
  ${DOSBOX_EXE_LIBS}
  libdosboxcommon
  libglad
  $<IF:$<TARGET_EXISTS:SDL2::SDL2>,SDL2::SDL2,SDL2::SDL2-static>
)

set_target_properties(DOSBoxerCore PROPERTIES
  INSTALL_NAME_DIR "@rpath"
  BUILD_WITH_INSTALL_NAME_DIR ON
)

# Only export the C API; everything else stays internal to the dylib
target_link_options(DOSBoxerCore PRIVATE
  "LINKER:-exported_symbols_list,${CMAKE_CURRENT_LIST_DIR}/exports.txt"
)
