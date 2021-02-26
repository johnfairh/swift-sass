<!--
swift-sass
README.md
Distributed under the MIT license, see LICENSE.
-->

![Platforms](https://img.shields.io/badge/platform-macOS%20%7C%20linux-lightgrey.svg)
[![codecov](https://codecov.io/gh/johnfairh/swift-sass/branch/main/graph/badge.svg?token=0NAP6IA9EB)](https://codecov.io/gh/johnfairh/swift-sass)
![Tests](https://github.com/johnfairh/swift-sass/workflows/Tests/badge.svg)

# Swift Sass

Embed the Dart [Sass](https://sass-lang.com) compiler in your Swift program.  Write
stylesheet importers and SassScript functions in Swift.

This package provides a Swift language interface to a separate Sass
implementation.  The `SassEmbedded` module lets you access
[Dart Sass](https://sass-lang.com/dart-sass),
the most up to date implementation of the Sass language.  It runs the
[Dart Sass compiler](https://github.com/sass/dart-sass) as a separate process
and communicates with it using the
[Sass embedded protocol](https://github.com/sass/embedded-protocol).  If you
come across another implementation of the 'compiler' side of the protocol then
that should work fine too.

The Sass embedding technology is pretty new.  Right now the [embedded compiler
releases](https://github.com/sass/dart-sass-embedded/releases) are all tagged
as alphas.

This package doesn't support LibSass right now.  [More info](#on-libsass).

* [Examples](#examples)
* [Documentation](#documentation)
* [Requirements](#requirements)
* [Installation](#installation)
* [Contributions](#contributions)
* [License](#license)

## Examples

Minimally:
```swift
import SassEmbedded

let compiler = try Compiler(eventLoopGroupProvider: .createNew)

let results = try compiler.compile(fileURL: scssFileURL)

print(results.css)
```
Although the compiler output is more structured, you'd probably be just as well
off running the binary directly.  The reason to use this package is to provide
custom implementations of `@use` rules to load content, and custom functions to
provide application-specific behavior:
```swift

struct ExtrasImporter: Importer {
  func canonicalize(importURL: String) throws -> URL? {
    guard importURL == "extras" else {
      return nil
    }
    return URL(string: "custom://extras")
  }

  func load(canonicalURL: URL) throws -> ImporterResults {
    ImporterResults(my_extras_stylesheet)
  }
}

let customFunctions: SassFunctionMap = [
  "userColorForScore($score)" : { args in
    let score = try args[0].asInt()
    return SassColor(...)
  }
]

let results = try compiler.compile(
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

These example are written in a synchronous style for simplicity.
`SassEmbedded` is built on
[NIO](https://github.com/apple/swift-nio) and there are corresponding
asynchronous / non-blocking APIs.

## Documentation

* [API documentation](https://johnfairh.github.io/swift-sass/)
* Dash docset [feed](dash-feed://https%3A%2F%2Fjohnfairh%2Egithub%2Eio%2Fswift%2Dsass%2Fdocsets%2Fswift%2Dsass%2Exml) or [direct download](https://johnfairh.github.io/swift-sass/docsets/swift-sass.tgz)

## Requirements

* Swift 5.3
* macOS 10.15+ (tested on macOS 10.15.7, macOS 11.0 IA64)
* Linux (tested on Ubuntu 18.04.5)
* Embedded Sass Protocol version 1.0.0-beta.8

## Installation

Only with Swift Package Manager, via Xcode or directly:
```swift
.package(name: "swift-sass",
         url: "https://github.com/johnfairh/swift-sass.git",
         from: "0.2.0")
```

The Swift package bundles the embedded Dart Sass compiler for macOS and Linux
(specifically Ubuntu Xenial/16.04 64-bit).  For other platforms you will need
to either download the correct version from
[the release page](https://github.com/sass/dart-sass-embedded/release) or build
it manually, ship it as part of your program's distribution, and use
[this initializer](https://johnfairh.github.io/swift-sass/sassembedded/types/compiler.html?swift#initeventloopgroupprovidertimeoutimportersfunctions).

There is no need to install a Dart runtime or SDK as part of this, the
`dart-embedded-sass` program is standalone.  The version required is
`1.0.0-beta.7`.

## On LibSass

[LibSass](https://sass-lang.com/libsass) is the C++ implementation of Sass.
In recent years it has fallen behind the specification and reference
implementations, and was
[deprecated in 2020](https://sass-lang.com/blog/libsass-is-deprecated).
However, work is underway to revive the project and it may be that LibSass 4
emerges as an alternative Sass implementation with the same level of language
support as Dart Sass.

This may eventually be a more convenient integration path for Swift programs and
this `swift-sass` package should support it as an alternative.

## Contributions

Welcome: open an issue / johnfairh@gmail.com / @johnfairh

## License

Distributed under the MIT license.
