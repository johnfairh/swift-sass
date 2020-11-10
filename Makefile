.PHONY: all build test test_linux protobuf

all: build

build:
	swift build

test:
	swift test --parallel

test_linux:
	docker run -v `pwd`:`pwd` -w `pwd` --name swift-sass --rm swift:5.3 swift test --parallel --enable-test-discovery

# Regenerate the protocol buffer structures.
# Only needed when the embedded-protocol submodule is changed.
# Failures here mean `brew install swift-protobuf` or suchlike is required
protobuf:
	protoc --version
	protoc --swift_out=Sources/DartSass --proto_path embedded-protocol embedded_sass.proto
