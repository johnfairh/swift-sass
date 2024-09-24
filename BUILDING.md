New swift-protobuf release:
* `brew upgrade swift-protobuf`
* `make protobuf`

New protocol release:
* Update `sass` to the new tag
* `make protobuf`
* Update `Versions.minProtocolVersion`
* Update README 'Requirements'

New `dart_sass` release:
* Update `VERSION_DART_SASS`
* Update README Sass badge
* `make dart_sass`
* Figure corresponding sass/sass release, update that tag
* `make deprecations` and check `Deprecations.swift`

New `swift-sass` release:
* `swift package update` & Xcode -> File -> Swift Packages -> Update...
* `.jazzy.yaml` - two places
* Update README 'Installation'
* Rebuild docs
* Update changelog
* Commit and tag
* Github release
