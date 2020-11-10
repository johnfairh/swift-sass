.PHONY: build test test_linux 

all: build

build:
	swift build

test:
	swift test --parallel

test_linux:
	docker run -v `pwd`:`pwd` -w `pwd` --name swift-sass --rm swift:5.3 swift test --parallel --enable-test-discovery

