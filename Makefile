.PHONY: all build test test_linux protobuf

all: build

build:
	swift build

ifeq ($(shell uname), Linux)
	platform ?= linux
else
	platform ?= macos
endif

test: Tests/EmbeddedSassTests/dart-sass-embedded/${platform}
	swift test --parallel --enable-test-discovery --enable-code-coverage

test_linux:
	docker run -v `pwd`:`pwd` -w `pwd` --name swift-sass --rm swift:5.3 make test

shell_linux:
	docker run -it -v `pwd`:`pwd` -w `pwd` --name swift-sass --rm swift:5.3 /bin/bash

# Regenerate the protocol buffer structures.
# Only needed when the embedded-protocol submodule is changed.
# Failures here mean `brew install swift-protobuf` or suchlike is required
protobuf:
	protoc --version
	protoc --swift_out=Sources/EmbeddedSass --proto_path embedded-protocol embedded_sass.proto

# Update the local copies of dart-sass-embedded for the test suite
# Ad-hoc and arch-dependent while this thing isn't available elsewhere.
sass_embedded_version=1.0.0-beta.5

sass_embedded_release_url=https://github.com/sass/dart-sass-embedded/releases/download/${sass_embedded_version}/sass_embedded-${sass_embedded_version}

Tests/EmbeddedSassTests/dart-sass-embedded/%:
	mkdir -p $@
	curl -L ${sass_embedded_release_url}-$*-x64.tar.gz | tar -xzv -C $@
