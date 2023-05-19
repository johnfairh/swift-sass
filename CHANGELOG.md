# 2.0.0-pre1

* Rewrite `Compiler` to be an actor and use `NIOAsyncChannel` to communicate
  with the compiler.  Interface is approximately the same; `syncShutdownGracefully()`
  is gone though to match NIO's approach.

* Shutdown behaviour has changed slightly: if you have compiler jobs running
  concurrently to a shutdown request then they are likely to be cancelled rather
  than left to run before actioning the shutdown.

* Make all Sass functions `async`: delete `SassFunction` types and then rename
  `SassAsyncFunction` types.

I expect to end the 'pre' series when `NIOAsyncChannel` is officially blessed;
there is also activity on the Sass side to do with reworking the protocol for
higher performance that may get rolled in here depending on timing and impact.

# 1.7.0

* Bundle the 1.60.0 `dart_sass_embedded` binaries

# 1.6.0

* Bundle the 1.54.2 `dart_sass_embedded` binaries -- this is the first release
  to include binaries for both arm64 and x86 architectures for both macOS and
  Linux, selecting the right one when the package is built.
* Support `includeCharset` option on compilations.

# 1.5.0

* Bundle the 1.53.0 `dart_sass_embedded` binaries

# 1.4.0

* Bundle the 1.50.1 `dart_sass_embedded` binaries

# 1.3.0

* Bundle the 1.49.10 `dart_sass_embedded` binaries

# 1.2.0

* Bundle the 1.49.9 `dart_sass_embedded` binaries

# 1.1.0

* Bundle the 1.49.8 `dart_sass_embedded` binaries

# 1.0.0

* Bundle the 1.49.7 `dart_sass_embedded` binaries
* Support generating source maps with embedded source stylesheets

# 0.8.0

* Bundle the 1.0.0-beta.14 `dart_sass_embedded` binaries
* Convert all interfaces to async/await
* Add `FilesystemImporter`

# 0.7.0

* Bundle the 1.0.0-beta.12 `dart_sass_embedded` binaries
* Add `SassCalculation`

# 0.6.0

* Bundle the 1.0.0-beta.11 `dart_sass_embedded` binaries
* Use `@spi` instead of underscored names to restrict `Sass` APIs
* Add `SassArgumentList`
* Make `.createNew` the default in `Compiler.init(...)`
* Add `SassValue.listCount`
* Support HWB-format `SassColor`s
* Fix `SassColor` multithreading bugs
* Fix `SassDynamicFunction` identity confusion

# 0.5.0

* Bundle the 1.0.0-beta-8 `dart_sass_embedded` binaries
* Revise swift-log levels per SSWG best practices
* Enable source maps by default
* Add `CompilerResults.withFileLocation(...)` to generate
  deployable source map and css files
* Add `CompilerResults.loadedURLs`
* Add `verboseDeprecations` and `suppressDependencyWarnings`
  flags to `Compiler` initializers to control deprecation warnings
* Require Swift 5.4

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
