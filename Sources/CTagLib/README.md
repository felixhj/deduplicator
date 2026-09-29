# CTagLib

[TagLib](https://taglib.org) built from source by SwiftPM, plus a small C
interface (`include/CTagLib.h`, `CTagLib.cpp`) so Swift can use it without C++
interop.

## Vendored code

| Directory | Source | Version |
|-----------|--------|---------|
| `taglib/` | `taglib/` from the TagLib release tarball | 2.3.2 |
| `utfcpp/` | `3rdparty/utfcpp/source/` from the same tarball | 4.2.0 |

The tarball is `taglib-2.3.2.tar.gz` from
<https://github.com/taglib/taglib/releases/tag/v2.3.2>, SHA-256
`3ca2d8afaa7f1cf7f6ed10e511ebc368bfacd6dcaa3dbfa690b89e502e8963dc`.

Only `.cpp`, `.h` and `.tcc` files were copied, unmodified. CMake files, tests,
examples, bindings and docs were left out. `config/` replaces the two headers
TagLib's CMake build generates, with every format enabled as in TagLib's
defaults.

## Updating

Download the new release tarball, check its SHA-256 against the GitHub release,
and replace `taglib/` and `utfcpp/` with the same copy step:

```sh
rsync -a --delete --include='*/' --include='*.cpp' --include='*.h' --include='*.tcc' \
    --exclude='*' taglib-X.Y.Z/taglib/ Sources/CTagLib/taglib/
rsync -a --delete taglib-X.Y.Z/3rdparty/utfcpp/source/ Sources/CTagLib/utfcpp/
```

Then compare `config.h.cmake` and `taglib/taglib_config.h.cmake` with `config/`,
and check `Package.swift` still lists every header directory.

## Licences

TagLib is available under the LGPL 2.1 or the MPL 1.1, and utfcpp under the
Boost Software License 1.0. The texts are in `licenses/`.
