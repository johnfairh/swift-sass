<!--
swift-sass
README.md
Distributed under the MIT license, see LICENSE.
-->

![Platforms](https://img.shields.io/badge/platform-macOS%20%7C%20linux-lightgrey.svg)
[![codecov](https://codecov.io/gh/johnfairh/swift-sass/branch/main/graph/badge.svg?token=0NAP6IA9EB)](https://codecov.io/gh/johnfairh/swift-sass)
![Tests](https://github.com/johnfairh/swift-sass/workflows/Tests/badge.svg)
![Sass](https://img.shields.io/badge/sass-1.83.4-purple)

# Swift Sass

Embed the Dart [Sass](https://sass-lang.com) compiler in your Swift program.  Write
stylesheet importers and SassScript functions in Swift.

This package provides a Swift language interface to a separate Sass
implementation.  The `DartSass` module lets you access
[Dart Sass](https://sass-lang.com/dart-sass),
the most up to date implementation of the Sass language.  It runs the
[Dart Sass compiler](https://github.com/sass/dart-sass) as a separate process
and communicates with it using the
[Sass embedded protocol](https://github.com/sass/sass/blob/main/spec/embedded-protocol.md).  If you
come across another implementation of the 'compiler' side of the protocol then
that should work fine too.

This package doesn't support LibSass right now.  [More info](#on-libsass).

## Examples

Minimally:
```swift
import DartSass

let compiler = try Compiler()

let results = try await compiler.compile(fileURL: scssFileURL)

print(results.css)
```
Although the compiler output is more structured, if this is all you want to do
then you're probably better off running the binary directly.  The reason to use
this package is to provide custom implementations of `@use` rules to load
content, and custom functions to provide application-specific behavior:
```swift

struct ExtrasImporter: Importer {
    func canonicalize(ruleURL: String, context: ImporterContext) async throws -> URL? {
      guard ruleURL == "extras" else {
      return nil
    }
    return URL(string: "custom://extras")
  }

  func load(canonicalURL: URL) async throws -> ImporterResults? {
    ImporterResults(my_extras_stylesheet)
  }
}

let customFunctions: SassFunctionMap = [
  "userColorForScore($score)" : { args in
    let score = try args[0].asInt()
    return SassColor(...)
  }
]

let results = try await compiler.compile(
    fileURL: scssFileURL,
    importers: [
      .loadPath(sassIncludeDirectoryFileURL),
      .importer(ExtrasImporter())
    ],
    functions: customFunctions
)
```

```scss
// stylesheet

@use "extras";

.score-mid {
  color: userColorForScore(50);
}
```

`DartSass` is built on [NIO](https://github.com/apple/swift-nio) but the user
interface is entirely Swift 5.5 async-await.

## Documentation

* [API documentation](https://johnfairh.github.io/swift-sass/)
* Dash docset [feed](dash-feed://https%3A%2F%2Fjohnfairh%2Egithub%2Eio%2Fswift%2Dsass%2Fdocsets%2Fswift%2Dsass%2Exml) or [direct download](https://johnfairh.github.io/swift-sass/docsets/swift-sass.tgz)

## Requirements

* Swift 6.0
* macOS 14+ (tested on macOS 14.x x64)
* Linux (tested on Ubuntu latest x64)
* Embedded Sass Protocol version 3.1.0

## Installation

Only with Swift Package Manager, via Xcode or directly:

Package dependency:
```swift
.package(name: "swift-sass",
         url: "https://github.com/johnfairh/swift-sass.git",
         from: "3.1.0")
```

Target dependency:
```swift
.product(name: "DartSass", package: "swift-sass"),
```

The Swift package bundles the Dart Sass compiler for macOS and Linux
(specifically Ubuntu Focal/20.04 64-bit) both x86_64 and arm64.  The correct
binary is selected at build time.  The selection is made based on the host
architecture though, so if you want to cross-compile you'll need to assemble
the results manually.

For other platforms you will need to either download the correct version from
[the release page](https://github.com/sass/dart-sass/release) or build
it manually, ship it as part of your program's distribution, and use
[this initializer](https://johnfairh.github.io/swift-sass/sassembedded/types/compiler.html?swift#initeventloopgroupprovidertimeoutimportersfunctions).

There is no need to install a Dart runtime or SDK as part of this, the
`dart-sass-embedded` program is standalone.  The version required is shown in
the [VERSION_DART_SASS](VERSION_DART_SASS) file.

## On LibSass

[LibSass](https://sass-lang.com/libsass) is the C++ implementation of Sass.
In recent years it has fallen behind the specification and reference
implementations, and was
[deprecated in 2020](https://sass-lang.com/blog/libsass-is-deprecated).
However, work is underway to revive the project and it may be that LibSass 4
or [libsass-ng](https://github.com/mgreter/libsass-ng/) emerges as an
alternative Sass implementation with the same level of language support as
Dart Sass.  As of summer 2024 this revival effort is showing signs of life but
I'm still not holding my breath.

See the experimental [libsass4 branch](https://github.com/johnfairh/swift-sass/tree/libsass4)
for the current state of development: if LibSass itself manages to get to a
release then this package will support it as an alternative integration.

## Contributions

Welcome: open an issue / johnfairh@gmail.com / @johnfairh@mastodon.social

## License

Distributed under the MIT license.
