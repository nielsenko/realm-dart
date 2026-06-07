// Shim for the MSVC-only <safeint.h>, which mingw-w64 does not ship.
//
// realm/util/safe_int_ops.hpp includes it under #ifdef _WIN32, but never
// actually uses msl::utilities::SafeInt — realm has its own
// SafeIntBinopsImpl. This empty shim satisfies the include on the
// *-windows-gnu target without patching the frozen realm-core submodule.
#pragma once
