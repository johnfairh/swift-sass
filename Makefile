.PHONY: all build test test_linux shell_linux protobuf dart_sass_embedded

all: build

build:
	swift build

test:
	swift test --enable-code-coverage

test_linux:
	docker run -v `pwd`:`pwd` -w `pwd` --name swift-sass --rm swift:5.4 make test

shell_linux:
	docker run -it -v `pwd`:`pwd` -w `pwd` --name swift-sass --rm swift:5.4 /bin/bash

# Regenerate the protocol buffer structures.
# Only needed when the embedded-protocol submodule is changed.
# Failures here mean `brew install swift-protobuf` or suchlike is required
protobuf:
	protoc --version
	protoc --swift_out=Sources/DartSass --proto_path embedded-protocol embedded_sass.proto

# Update the local copies of dart-sass-embedded 
# Only needed when there's a new release of the compiler to pick up
sass_embedded_version := 1.0.0-beta.10

sass_embedded_release_url := https://github.com/sass/dart-sass-embedded/releases/download/${sass_embedded_version}/sass_embedded-${sass_embedded_version}

dart_sass_embedded:
	curl -L ${sass_embedded_release_url}-macos-x64.tar.gz | tar -xzv -C Sources/DartSassEmbeddedMacOS
	curl -L ${sass_embedded_release_url}-linux-x64.tar.gz | tar -xzv -C Sources/DartSassEmbeddedLinux
