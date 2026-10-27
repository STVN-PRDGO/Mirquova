cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Read the installed version from the same manifest used by Flutter.
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${CMAKE_SOURCE_DIR}/../pubspec.yaml")
file(STRINGS "${CMAKE_SOURCE_DIR}/../pubspec.yaml" MIRQUOVA_PACKAGE_VERSION REGEX "^version: ")
string(REGEX REPLACE "^version: ([0-9.]+)\\+([0-9]+)$" "\\1" MIRQUOVA_VERSION "${MIRQUOVA_PACKAGE_VERSION}")
string(REGEX REPLACE "^version: ([0-9.]+)\\+([0-9]+)$" "\\2" MIRQUOVA_BUILD "${MIRQUOVA_PACKAGE_VERSION}")
target_compile_definitions(${BINARY_NAME} PRIVATE
  MIRQUOVA_VERSION="${MIRQUOVA_VERSION}"
  MIRQUOVA_BUILD="${MIRQUOVA_BUILD}")
