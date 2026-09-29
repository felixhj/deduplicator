/* Replaces the config.h that TagLib's CMake build generates from config.h.cmake. */

#ifndef TAGLIB_CONFIG_H
#define TAGLIB_CONFIG_H

/* Clang and GCC both provide __builtin_bswap16/32/64. */
#define HAVE_GCC_BYTESWAP 1

/* zlib ships with the macOS SDK. TagLib only uses it for compressed ID3v2 frames,
   so Linux builds leave it out rather than depend on zlib headers being installed. */
#if defined(__APPLE__)
#define HAVE_ZLIB 1
#endif

#endif
