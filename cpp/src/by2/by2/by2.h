#pragma once
#include <stdint.h>

// Export / import mechanics
// When building as a shared library (BY2_SHARED option ON), CMake will define:
//   BY2_BUILD_SHARED privately for the by2 target itself
//   BY2_USE_SHARED publicly for dependents (consumers)
// On Windows we map these to __declspec(dllexport/dllimport). On other platforms
// we use GCC/Clang visibility if available; static builds leave BY2_API empty.
#if defined(_WIN32) || defined(__CYGWIN__)
#if defined(BY2_BUILD_SHARED)
#define BY2_API __declspec(dllexport)
#elif defined(BY2_USE_SHARED)
#define BY2_API __declspec(dllimport)
#else
#define BY2_API
#endif
#else
#if defined(BY2_BUILD_SHARED) && (__GNUC__ >= 4)
#define BY2_API __attribute__((visibility("default")))
#else
#define BY2_API
#endif
#endif

#ifdef __cplusplus
extern "C"
{
#endif

    BY2_API int32_t by2_add(int32_t a, int32_t b);

#ifdef __cplusplus
} // extern "C"
#endif