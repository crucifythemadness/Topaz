# Writes topaz_build_date.h (TOPAZ_BUILD_DATE, e.g. "Oct 16 2026") for the
# About dialog's BUILT chip. Run on EVERY build by the topaz_build_date target
# in CMakeLists.txt, but the file is only rewritten when the date actually
# changed -- so buildinfo.cpp recompiles once per day, not on every build.
# (Plain __DATE__ in buildinfo.cpp was only refreshed when that file itself was
# recompiled, so the chip kept showing an old day.)
string(TIMESTAMP _date "%b %d %Y")
set(_content "#pragma once\n#define TOPAZ_BUILD_DATE \"${_date}\"\n")
if(EXISTS "${OUT}")
    file(READ "${OUT}" _old)
else()
    set(_old "")
endif()
if(NOT _old STREQUAL _content)
    file(WRITE "${OUT}" "${_content}")
endif()
