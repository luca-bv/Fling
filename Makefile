APP := build/Fling.app
# Ad-hoc signing ("-") changes the signature every build, so macOS forgets the Accessibility grant.
# `make cert` creates a stable self-signed identity; builds use it automatically once it exists.
CERT_NAME := Fling Dev
SIGN_IDENTITY ?= $(shell security find-certificate -c "$(CERT_NAME)" >/dev/null 2>&1 && echo "$(CERT_NAME)" || echo -)
# Command Line Tools ship Swift Testing here but don't add it to the search path.
CLT_FRAMEWORKS := /Library/Developer/CommandLineTools/Library/Developer/Frameworks

.PHONY: app run test smoke clean cert install-cli dmg
PREFIX ?= $(HOME)/.local
VERSION ?= 0.1.0
BUILD_NUMBER ?= $(shell git rev-list --count HEAD 2>/dev/null || echo 1)
# UNIVERSAL=1 builds for Apple Silicon and Intel (used by `make dmg`); plain builds are for this Mac only.
UNIVERSAL ?= 0
BIN := $(if $(filter 1,$(UNIVERSAL)),.build/universal,.build/release)

app:
ifeq ($(UNIVERSAL),1)
	swift build -c release --triple arm64-apple-macosx14.0 --scratch-path .build/arm64
	swift build -c release --triple x86_64-apple-macosx14.0 --scratch-path .build/x86_64
	mkdir -p $(BIN)
	for binary in Fling flingctl; do \
		lipo -create .build/arm64/release/$$binary .build/x86_64/release/$$binary -output $(BIN)/$$binary; \
	done
else
	swift build -c release
endif
	rm -rf $(APP) && mkdir -p $(APP)/Contents/MacOS
	cp $(BIN)/Fling $(BIN)/flingctl $(APP)/Contents/MacOS/
	printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
		'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
		'<plist version="1.0"><dict>' \
		'<key>CFBundleIdentifier</key><string>com.lucabv.Fling</string>' \
		'<key>CFBundleName</key><string>Fling</string>' \
		'<key>CFBundleExecutable</key><string>Fling</string>' \
		'<key>CFBundlePackageType</key><string>APPL</string>' \
		'<key>CFBundleShortVersionString</key><string>$(VERSION)</string>' \
		'<key>CFBundleVersion</key><string>$(BUILD_NUMBER)</string>' \
		'<key>NSHumanReadableCopyright</key><string>© 2026 luca-bv. MIT License.</string>' \
		'<key>LSMinimumSystemVersion</key><string>14.0</string>' \
		'<key>LSUIElement</key><true/>' \
		'<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>com.lucabv.Fling</string>' \
		'<key>CFBundleURLSchemes</key><array><string>fling</string></array></dict></array>' \
		'</dict></plist>' > $(APP)/Contents/Info.plist
	codesign --force --sign "$(SIGN_IDENTITY)" $(APP)/Contents/MacOS/flingctl
	codesign --force --sign "$(SIGN_IDENTITY)" $(APP)

run: app
	open $(APP)

test:
	@if [ -d $(CLT_FRAMEWORKS) ] && ! xcode-select -p | grep -q Xcode.app; then \
		swift test -Xswiftc -F -Xswiftc $(CLT_FRAMEWORKS) -Xlinker -F -Xlinker $(CLT_FRAMEWORKS) -Xlinker -rpath -Xlinker $(CLT_FRAMEWORKS); \
	else swift test; fi

# Runs real window actions through the Accessibility API against a throwaway test window and prints PASS/FAIL.
# Runs beside the Fling you already have open: --smoke-test takes no hotkeys or event tap and uses its own
# socket, and both apps launch in the background (-g) so nothing steals focus while you work.
TEST_WINDOW := build/FlingTestWindow.app
smoke: app
	rm -rf $(TEST_WINDOW) && mkdir -p $(TEST_WINDOW)/Contents/MacOS
	swiftc -O Tests/Smoke/TestWindow.swift -o $(TEST_WINDOW)/Contents/MacOS/FlingTestWindow
	printf '%s' '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>' \
		'<key>CFBundleIdentifier</key><string>com.lucabv.Fling.TestWindow</string>' \
		'<key>CFBundleExecutable</key><string>FlingTestWindow</string>' \
		'<key>CFBundlePackageType</key><string>APPL</string></dict></plist>' > $(TEST_WINDOW)/Contents/Info.plist
	codesign --force --sign - $(TEST_WINDOW)
	@pkill -x FlingTestWindow; open -g -n $(TEST_WINDOW); sleep 2; log=$$(mktemp) && \
	open -g -W -n --stdout "$$log" --stderr "$$log" $(APP) --args --smoke-test com.lucabv.Fling.TestWindow; \
	cat "$$log"; pkill -x FlingTestWindow; ! grep -q FAIL "$$log"

# Links flingctl (inside the app bundle) into $(PREFIX)/bin, ~/.local/bin by default.
install-cli: app
	mkdir -p "$(PREFIX)/bin"
	ln -sf "$(CURDIR)/$(APP)/Contents/MacOS/flingctl" "$(PREFIX)/bin/flingctl"
	@echo "Installed $(PREFIX)/bin/flingctl"

# A universal, signed app in a drag-to-Applications disk image: build/Fling-$(VERSION).dmg
# Sign with the same "Fling Dev" certificate every release, or testers have to grant Accessibility again.
DMG := build/Fling-$(VERSION).dmg
dmg:
	@test "$(SIGN_IDENTITY)" != "-" || { echo "Run \`make cert\` first: ad-hoc builds lose testers' permissions on every update."; exit 1; }
	$(MAKE) app UNIVERSAL=1
	rm -rf build/dmg $(DMG) && mkdir -p build/dmg
	ditto $(APP) build/dmg/Fling.app
	ln -s /Applications build/dmg/Applications
	cp "release/Read Me First.txt" build/dmg/
	hdiutil create -volname "Fling $(VERSION)" -srcfolder build/dmg -fs HFS+ -format UDZO -ov $(DMG)
	codesign --force --sign "$(SIGN_IDENTITY)" $(DMG)
	rm -rf build/dmg
	@echo "Built $(DMG)"

clean:
	rm -rf .build build

# One-time: a self-signed code signing certificate in the login keychain, usable by codesign without prompts.
cert:
	@security find-certificate -c "$(CERT_NAME)" >/dev/null 2>&1 && { echo "$(CERT_NAME) already exists"; exit 0; }; \
	dir=$$(mktemp -d) && trap 'rm -rf "$$dir"' EXIT && \
	/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$(CERT_NAME)" \
		-addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" \
		-addext "basicConstraints=critical,CA:false" -keyout "$$dir/key.pem" -out "$$dir/cert.pem" 2>/dev/null && \
	/usr/bin/openssl pkcs12 -export -inkey "$$dir/key.pem" -in "$$dir/cert.pem" -out "$$dir/cert.p12" -passout pass:fling && \
	security import "$$dir/cert.p12" -k ~/Library/Keychains/login.keychain-db -P fling -T /usr/bin/codesign && \
	echo "Created $(CERT_NAME)"
