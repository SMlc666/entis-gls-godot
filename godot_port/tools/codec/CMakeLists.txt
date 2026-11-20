cmake_minimum_required(VERSION 3.18)
project(yzk_codec LANGUAGES CXX)

if(NOT DEFINED AU_SOURCE_DIR OR NOT EXISTS "${AU_SOURCE_DIR}/src/dec/entis/common/erisan_decoder.cc")
  message(FATAL_ERROR "AU_SOURCE_DIR must point to the pinned arc_unpacker source tree")
endif()
if(NOT DEFINED GODOTCPP_SOURCE_DIR OR NOT EXISTS "${GODOTCPP_SOURCE_DIR}/CMakeLists.txt")
  message(FATAL_ERROR "GODOTCPP_SOURCE_DIR must point to the pinned godot-cpp source tree")
endif()

set(GODOTCPP_DEFAULT_API_VERSION "4.7" CACHE STRING "Godot GDExtension API version")
set(GODOTCPP_API_VERSION "4.7" CACHE STRING "Godot GDExtension API version")
set(GODOTCPP_TARGET "template_release" CACHE STRING "godot-cpp target profile")
add_subdirectory("${GODOTCPP_SOURCE_DIR}" "${CMAKE_BINARY_DIR}/godot-cpp")

file(GLOB_RECURSE AU_ENTIS_SOURCES CONFIGURE_DEPENDS "${AU_SOURCE_DIR}/src/dec/entis/*.cc")
list(FILTER AU_ENTIS_SOURCES EXCLUDE REGEX "/noa_archive_decoder\\.cc$")

add_library(yzk_codec SHARED
  "${CMAKE_CURRENT_LIST_DIR}/../yzk_codec.cc"
  "${AU_SOURCE_DIR}/src/types.cc"
  "${AU_SOURCE_DIR}/src/err.cc"
  "${AU_SOURCE_DIR}/src/algo/format.cc"
  "${AU_SOURCE_DIR}/src/arg_parser_decorator.cc"
  "${AU_SOURCE_DIR}/src/dec/base_audio_decoder.cc"
  "${AU_SOURCE_DIR}/src/dec/base_decoder.cc"
  "${AU_SOURCE_DIR}/src/dec/base_image_decoder.cc"
  "${AU_SOURCE_DIR}/src/dec/registry.cc"
  "${AU_SOURCE_DIR}/src/io/base_bit_stream.cc"
  "${AU_SOURCE_DIR}/src/io/base_byte_stream.cc"
  "${AU_SOURCE_DIR}/src/io/base_stream.cc"
  "${AU_SOURCE_DIR}/src/io/memory_byte_stream.cc"
  "${AU_SOURCE_DIR}/src/io/msb_bit_stream.cc"
  "${AU_SOURCE_DIR}/src/logger.cc"
  "${AU_SOURCE_DIR}/src/logger_dummy.cc"
  "${AU_SOURCE_DIR}/src/res/audio.cc"
  "${AU_SOURCE_DIR}/src/res/image.cc"
  "${AU_SOURCE_DIR}/src/res/palette.cc"
  "${AU_SOURCE_DIR}/src/res/pixel_format.cc"
  ${AU_ENTIS_SOURCES}
)
target_include_directories(yzk_codec PRIVATE "${AU_SOURCE_DIR}/src")
target_link_libraries(yzk_codec PRIVATE godot-cpp)
target_compile_features(yzk_codec PRIVATE cxx_std_17)
target_compile_options(yzk_codec PRIVATE -include cstdint)
target_link_options(yzk_codec PRIVATE -Wl,--no-undefined)
set_target_properties(yzk_codec PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON
  POSITION_INDEPENDENT_CODE ON
  OUTPUT_NAME "yzk_codec"
)
