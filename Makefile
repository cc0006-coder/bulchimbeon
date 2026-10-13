# Command Line Tools 의 Testing.framework 는 _Testing_Foundation 모듈이 빠져 있어
# cross-import overlay 를 끄고 프레임워크 경로를 직접 지정한다. (Xcode 설치 환경에서는 `swift test` 로 충분)
TESTING_FW := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
TEST_FLAGS := $(if $(wildcard $(TESTING_FW)),-Xswiftc -F$(TESTING_FW) -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays -Xlinker -rpath -Xlinker $(TESTING_FW))

.PHONY: build test app run icons clean

build:
	swift build

test:
	swift test $(TEST_FLAGS)

# 스프라이트(Sources/BulchimbeonCore/Sprites.swift) 수정 후 실행 → 앱 아이콘·미리보기 갱신
icons:
	swift run IconGen .build/icons
	iconutil -c icns .build/icons/AppIcon.iconset -o Resources/AppIcon.icns
	cp .build/icons/sprites-preview.png docs/sprites-preview.png

app:
	./scripts/build-app.sh

run: app
	open dist/Bulchimbeon.app

clean:
	rm -rf .build dist
