.PHONY: all build test test_linux shell_linux protobuf dart_sass

all: build

build:
	swift build

test:
	swift test --enable-code-coverage

test_linux:
	docker run -v `pwd`:`pwd` -w `pwd` --name swift-sass --rm swift:6.2 swift test

shell_linux:
	docker run -it -v `pwd`:`pwd` -w `pwd` --name swift-sass --rm swift:6.2 /bin/bash

# Regenerate the protocol buffer structures.
# Only needed when the embedded-protocol submodule is changed.
# Failures here mean `brew install swift-protobuf` or suchlike is required
protobuf:
	protoc --version
	protoc --swift_out=Sources/DartSass --proto_path sass/spec embedded_sass.proto

# Update the local copies of dart-sass
# Only needed when there's a new release of the compiler to pick up
dart_sass_version := $(shell cat VERSION_DART_SASS)

dart_sass_release_url := https://github.com/sass/dart-sass/releases/download/${dart_sass_version}/dart-sass-${dart_sass_version}

dart_sass:
	curl -L ${dart_sass_release_url}-macos-x64.tar.gz | tar -xzv -C Sources/DartSassEmbeddedMacOS/x64
	curl -L ${dart_sass_release_url}-macos-arm64.tar.gz | tar -xzv -C Sources/DartSassEmbeddedMacOS/arm64
	curl -L ${dart_sass_release_url}-linux-x64.tar.gz | tar -xzv -C Sources/DartSassEmbeddedLinux/x64
	curl -L ${dart_sass_release_url}-linux-arm64.tar.gz | tar -xzv -C Sources/DartSassEmbeddedLinux/arm64

deprecations:
	@grep '^[a-z]\S.*:' sass/spec/deprecations.yaml | sed 's/://' | sort -n
	@grep '^[a-z]\S.*:' sass/spec/deprecations.yaml | wc -l
