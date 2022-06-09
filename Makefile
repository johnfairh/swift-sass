.PHONY: all build test test_linux shell_linux protobuf dart_sass_embedded libsass4

all: build

# This gorp is only required while we use a private libsass *and* have
# a real libsass installed in a normal place
libsass4flags := \
	-Xcc -I${CURDIR} \
	-Xcc -I${CURDIR}/libsass4/include \
	-Xlinker -L${CURDIR}/libsass4/lib \
	-Xlinker -rpath -Xlinker ${CURDIR}/libsass4/lib

build:
	swift build ${libsass4flags}

swifttestflags := --enable-code-coverage

test:
	swift test ${swifttestflags} ${libsass4flags}

test_libsass:
	swift test ${swifttestflags} --filter LibSassTests ${libsass4flags}

test_linux:
	docker run -v `pwd`:`pwd` -w `pwd` --name swift-sass --rm swift:5.6 make test

shell_linux:
	docker run -it -v `pwd`:`pwd` -w `pwd` --name swift-sass --rm swift:5.6 /bin/bash

# Regenerate the protocol buffer structures.
# Only needed when the embedded-protocol submodule is changed.
# Failures here mean `brew install swift-protobuf` or suchlike is required
protobuf:
	protoc --version
	protoc --swift_out=Sources/DartSass --proto_path embedded-protocol embedded_sass.proto

# Update the local copies of dart-sass-embedded 
# Only needed when there's a new release of the compiler to pick up
sass_embedded_version := $(shell cat VERSION_DART_SASS)

sass_embedded_release_url := https://github.com/sass/dart-sass-embedded/releases/download/${sass_embedded_version}/sass_embedded-${sass_embedded_version}

dart_sass_embedded:
	curl -L ${sass_embedded_release_url}-macos-x64.tar.gz | tar -xzv -C Sources/DartSassEmbeddedMacOS
	curl -L ${sass_embedded_release_url}-linux-x64.tar.gz | tar -xzv -C Sources/DartSassEmbeddedLinux

# Rebuild the alpha libsass4
# Only needed when the libsass4 submodule is bumped
libsass4:
	cd libsass4 && CXXFLAGS="-Wall -mmacosx-version-min=10.15" LDFLAGS="-Wall -mmacosx-version-min=10.15" BUILD="shared" LIBSASS_VERSION=4.0.0-beta.johnf make -j5

libsass4_debug:
	cd libsass4 && CXXFLAGS="-Wall -mmacosx-version-min=10.15 -DDEBUG_SHARED_PTR" LDFLAGS="-Wall -mmacosx-version-min=10.15" BUILD="shared" DEBUG=1 LIBSASS_VERSION=4.0.0-beta.johnf make -j5
