.PHONY: all build install uninstall clean

VERSION := $(shell cat VERSION)
BUILD_NUMBER ?= $(shell git rev-list --count HEAD 2>/dev/null || echo 1)

all:
	@echo "run 'make build' to build the keywi gui application"

# builds the gui application
build:
	make clean
	mkdir -p build/Keywi.app/Contents/MacOS build/Keywi.app/Contents/Resources build/Keywi.iconset

	swiftc -target x86_64-apple-macos12.4 src/app/main.swift -o build/main-amd64
	swiftc -target arm64-apple-macos12.4 src/app/main.swift -o build/main-arm64

	lipo -create build/main-amd64 build/main-arm64 -o build/Keywi
	chmod +x build/Keywi

	cp build/Keywi build/Keywi.app/Contents/MacOS/Keywi
	/usr/bin/sips -z 16 16 assets/logo.png --out build/Keywi.iconset/icon_16x16.png
	/usr/bin/sips -z 32 32 assets/logo.png --out build/Keywi.iconset/icon_16x16@2x.png
	/usr/bin/sips -z 32 32 assets/logo.png --out build/Keywi.iconset/icon_32x32.png
	/usr/bin/sips -z 64 64 assets/logo.png --out build/Keywi.iconset/icon_32x32@2x.png
	/usr/bin/sips -z 128 128 assets/logo.png --out build/Keywi.iconset/icon_128x128.png
	/usr/bin/sips -z 256 256 assets/logo.png --out build/Keywi.iconset/icon_128x128@2x.png
	/usr/bin/sips -z 256 256 assets/logo.png --out build/Keywi.iconset/icon_256x256.png
	/usr/bin/sips -z 512 512 assets/logo.png --out build/Keywi.iconset/icon_256x256@2x.png
	/usr/bin/sips -z 512 512 assets/logo.png --out build/Keywi.iconset/icon_512x512.png
	/usr/bin/sips -z 1024 1024 assets/logo.png --out build/Keywi.iconset/icon_512x512@2x.png
	/usr/bin/iconutil -c icns build/Keywi.iconset -o build/Keywi.app/Contents/Resources/Keywi.icns
	/usr/bin/plutil -create xml1 build/Keywi.app/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.emilmair.keywi" build/Keywi.app/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Add :CFBundleName string Keywi" build/Keywi.app/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string Keywi" build/Keywi.app/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string Keywi.icns" build/Keywi.app/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" build/Keywi.app/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $(BUILD_NUMBER)" build/Keywi.app/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $(VERSION)" build/Keywi.app/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" build/Keywi.app/Contents/Info.plist
	/usr/bin/codesign --force --sign - build/Keywi.app
	rm -rf build/Keywi.iconset

# installs the cli application
install:
	cp src/cli/keywi /usr/local/bin/keywi
	cp VERSION /usr/local/bin/keywi.version

# uninstalls the cli application
uninstall:
	rm /usr/local/bin/keywi /usr/local/bin/keywi.version

clean:
	rm -rf build/*
