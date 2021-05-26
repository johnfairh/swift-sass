# Main

## Breaking

* Require Swift 5.4

## Enhancements

* Revise swift-log levels per SSWG best practices
* Enable source maps by default
* Add `CompilerResults.withFileLocation(...)` to generate
  deployable source map and css files

## Bug Fixes

* None

# 0.4.0

* Rename module `SassEmbedded` to `DartSass`
* Move various importer types from `Sass` into `DartSass`
* Always use host process's view of current directory

# 0.3.0

* Bundle the 1.0.0-beta.7 `dart_sass_embedded` binaries
* Remove unsupported CSS output styles
* Support colorized diagnostic messages

# 0.2.0

* Bundle the 1.0.0-beta.6 `dart_sass_embedded` binaries
* Take out the 'search $PATH' `Compiler` initializer
* Support importer on compile-string interfaces
* Surface compiler versions (currently faked out)

# 0.1.1

* Use https:// for submodule links

# 0.1.0

First complete release
