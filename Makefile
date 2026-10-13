# Command Line Tools 의 Testing.framework 는 _Testing_Foundation 모듈이 빠져 있어
# cross-import overlay 를 끄고 프레임워크 경로를 직접 지정한다. (Xcode 설치 환경에서는 `swift test` 로 충분)
TESTING_FW := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
TEST_FLAGS := $(if $(wildcard $(TESTING_FW)),-Xswiftc -F$(TESTING_FW) -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays -Xlinker -rpath -Xlinker $(TESTING_FW))

.PHONY: build test app run clean

build:
	swift build

test:
	swift test $(TEST_FLAGS)

app:
	./scripts/build-app.sh

run: app
	open dist/Bulchimbeon.app

clean:
	rm -rf .build dist
