<!--
swift-sass
README.md
Distributed under the MIT license, see LICENSE.
-->

![Platforms](https://img.shields.io/badge/platform-macOS%20%7C%20linux-lightgrey.svg)
[![codecov](https://codecov.io/gh/johnfairh/ss/branch/main/graph/badge.svg?token=0NAP6IA9EB)](https://codecov.io/gh/johnfairh/ss)
![Tests](https://github.com/johnfairh/ss/workflows/Tests/badge.svg)

# Swift Sass

Embed a [Sass](https://sass-lang.com) compiler in your Swift program.  Write
custom importers and SassScript functions in Swift.

This package provides a Swift language interface to a separate Sass implementation.
The `EmbeddedSass` module lets you access Dart Sass, the most up to date implementation
of the Sass language.  It runs the Dart Sass compiler as a separate process and
communicates with it using the Embedded Sass protocol.  If you come across another
implementation of the 'compiler' end of that protocol then that should work fine too.

The Embedded Sass technology is pretty new.  Right now the embedded compiler releases
are all tagged as alphas.

This package doesn't support libsass right now.  [More info](#on-libsass).

# Example

Minimally:
```swift
import EmbeddedSass

let compiler = try Compiler(eventLoopGroupProvider: .createNew,
                            embeddedCompilerURL: dartSassEmbeddedFileURL)

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
`EmbeddedSass` is built on [NIO](swift-nio) and there are corresponding
asynchronous / non-blocking APIs.

# Documentation

# Requirements

* Swift 5.3
* macOS 10.15+ (tested on macOS 10.15.7, macOS 11.0 IA64)
* Linux (tested on Ubuntu 18.04.5)
* Dart Sass Embedded version 1.0.0-beta.5

Should work on other Swift platforms though may need some minor portage.

# Installation

Only as Swift Package Manager modules via Xcode or directly:
```swift
???
```

The Swift modules do not bundle the embedded Dart Sass compiler: right now
you need to download it from [the release page](linky).  There is no need to
install a Dart runtime or SDK, the downloaded package is standalone.

# On LibSass

LibSass is the C++ implementation of Sass.  In recent years it has fallen behind
the specification and reference implementations, and was formally deprecated in
2020.  However, work is afoot to revive the project and it may be that
LibSass 4.0 emerges as an undeprecated Sass implementation with the same level
of language support as Dart Sass.

This may eventually be a more convenient integration path for Swift programs and
this `swift-sass` package should support it as an alternative, sharing all of
the SassScript types in the `Sass` module.
