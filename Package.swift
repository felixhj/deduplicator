// swift-tools-version: 6.0
import PackageDescription

/// Every folder in TagLib's source tree that holds headers. TagLib's sources
/// include each other by bare file name, so each one is a search path.
let tagLibHeaderFolders = [
    "taglib",
    "taglib/ape",
    "taglib/asf",
    "taglib/dsdiff",
    "taglib/dsf",
    "taglib/flac",
    "taglib/it",
    "taglib/matroska",
    "taglib/matroska/ebml",
    "taglib/mod",
    "taglib/mp4",
    "taglib/mpc",
    "taglib/mpeg",
    "taglib/mpeg/id3v1",
    "taglib/mpeg/id3v2",
    "taglib/mpeg/id3v2/frames",
    "taglib/ogg",
    "taglib/ogg/flac",
    "taglib/ogg/opus",
    "taglib/ogg/speex",
    "taglib/ogg/vorbis",
    "taglib/riff",
    "taglib/riff/aiff",
    "taglib/riff/wav",
    "taglib/s3m",
    "taglib/shorten",
    "taglib/toolkit",
    "taglib/trueaudio",
    "taglib/wavpack",
    "taglib/xm",
]

let package = Package(
    name: "Deduplicator",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DedupCore", targets: ["DedupCore"]),
        .library(name: "DedupScanner", targets: ["DedupScanner"]),
    ],
    targets: [
        .target(name: "DedupCore"),
        .target(
            name: "CTagLib",
            exclude: ["README.md", "licenses"],
            cxxSettings: [
                .headerSearchPath("config"),
                .headerSearchPath("utfcpp"),
                .define("HAVE_CONFIG_H"),
                .define("TAGLIB_STATIC"),
                // Silences TagLib's debug messages about malformed files.
                .define("NDEBUG"),
            ] + tagLibHeaderFolders.map { .headerSearchPath($0) },
            linkerSettings: [.linkedLibrary("z", .when(platforms: [.macOS]))]
        ),
        .target(name: "DedupScanner", dependencies: ["DedupCore", "CTagLib"]),
        .testTarget(name: "DedupCoreTests", dependencies: ["DedupCore"]),
        .testTarget(name: "DedupScannerTests", dependencies: ["DedupScanner", "DedupCore"]),
    ],
    cxxLanguageStandard: .cxx17
)
