SWIFTC=swiftc
TARGET=GestureDaemon
BUNDLE_ID=com.guru.GestureDaemon
BUILD_DIR=./build
APP_NAME=GestureDaemon.app
APP_BUNDLE=$(BUILD_DIR)/$(APP_NAME)
SRC=$(shell find GestureDaemon -name "*.swift")
ENTITLEMENTS=GestureDaemon.entitlements
INSTALL_BIN=/usr/local/bin/$(TARGET)
LAUNCH_AGENT_DIR=$(HOME)/Library/LaunchAgents
AGENT_PLIST=scripts/com.user.gesturedaemon.plist
SDK=$(shell xcrun --show-sdk-path)

.PHONY: all clean build build-arm64 build-x86_64 build-universal app app-arm64 app-x86_64 app-universal dmg run diagnose install uninstall disable-logi enable-logi stop-logi start-logi

all: clean app dmg

build-arm64:
	@echo "==> Compiling GestureDaemon (arm64 - Apple Silicon)..."
	@mkdir -p $(BUILD_DIR)/cache
	$(SWIFTC) -O -module-cache-path $(BUILD_DIR)/cache -target arm64-apple-macos13.0 -sdk $(SDK) $(SRC) -o $(BUILD_DIR)/$(TARGET)-arm64
	@codesign --force --sign - --identifier "$(BUNDLE_ID)" --entitlements $(ENTITLEMENTS) $(BUILD_DIR)/$(TARGET)-arm64
	@echo "==> arm64 build complete: $(BUILD_DIR)/$(TARGET)-arm64"

build-x86_64:
	@echo "==> Compiling GestureDaemon (x86_64 - Intel)..."
	@mkdir -p $(BUILD_DIR)/cache
	$(SWIFTC) -O -module-cache-path $(BUILD_DIR)/cache -target x86_64-apple-macos13.0 -sdk $(SDK) $(SRC) -o $(BUILD_DIR)/$(TARGET)-x86_64
	@codesign --force --sign - --identifier "$(BUNDLE_ID)" --entitlements $(ENTITLEMENTS) $(BUILD_DIR)/$(TARGET)-x86_64
	@echo "==> x86_64 build complete: $(BUILD_DIR)/$(TARGET)-x86_64"

build: build-arm64 build-x86_64
	@echo "==> Fusing universal binary (arm64 + x86_64)..."
	lipo -create -output $(BUILD_DIR)/$(TARGET) $(BUILD_DIR)/$(TARGET)-arm64 $(BUILD_DIR)/$(TARGET)-x86_64
	@echo "==> Code signing binary (identifier: $(BUNDLE_ID))..."
	codesign --force --sign - --identifier "$(BUNDLE_ID)" --entitlements $(ENTITLEMENTS) $(BUILD_DIR)/$(TARGET)
	@echo "==> Universal build complete: $(BUILD_DIR)/$(TARGET)"

build-universal: build

define package_app
	@echo "==> Packaging $(APP_NAME) ($1)..."
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp $(BUILD_DIR)/$(TARGET)$2 $(APP_BUNDLE)/Contents/MacOS/$(TARGET)
	@cp GestureDaemon/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	@if [ -d GestureDaemon/Resources ]; then \
		cp -R GestureDaemon/Resources/* $(APP_BUNDLE)/Contents/Resources/ 2>/dev/null || true; \
	fi
	@cp GestureDaemon/Configuration/config.plist $(APP_BUNDLE)/Contents/Resources/default_config.plist
	@echo "==> Code signing $(APP_NAME)..."
	codesign --force --deep --sign - --identifier "$(BUNDLE_ID)" --entitlements $(ENTITLEMENTS) $(APP_BUNDLE)
	@echo "==> Application bundle complete ($1): $(APP_BUNDLE)"
endef

app: build
	$(call package_app,universal,)

app-universal: app

app-arm64: build-arm64
	$(call package_app,arm64,-arm64)

app-x86_64: build-x86_64
	$(call package_app,x86_64,-x86_64)

dmg: app
	@echo "==> Generating distribution disk image (.dmg)..."
	@./scripts/create_dmg.sh

run: app
	@pkill -9 -x $(TARGET) 2>/dev/null || true
	@sleep 0.5
	@echo "==> Launching $(APP_NAME)..."
	open $(APP_BUNDLE)

diagnose: app
	@pkill -9 -x $(TARGET) 2>/dev/null || true
	@sleep 0.5
	@echo "==> Diagnostic mode. Ctrl+C to exit."
	$(APP_BUNDLE)/Contents/MacOS/$(TARGET) --diagnostics

install: app
	@echo "==> Terminating any running GestureDaemon..."
	@pkill -9 -x $(TARGET) 2>/dev/null || true
	@sleep 0.5
	@echo "==> Installing $(APP_NAME) to /Applications..."
	@rm -rf /Applications/$(APP_NAME)
	@cp -R $(APP_BUNDLE) /Applications/
	@echo "==> Launching /Applications/$(APP_NAME)..."
	open /Applications/$(APP_NAME)
	@echo "==> Installed and running. Use menu bar icon to toggle Launch at Login."

uninstall:
	@echo "==> Terminating GestureDaemon..."
	killall GestureDaemon 2>/dev/null || true
	@rm -rf /Applications/$(APP_NAME)
	@launchctl unload $(LAUNCH_AGENT_DIR)/com.user.gesturedaemon.plist 2>/dev/null || true
	@rm -f $(LAUNCH_AGENT_DIR)/com.user.gesturedaemon.plist
	@sudo rm -f $(INSTALL_BIN) 2>/dev/null || true
	@echo "==> GestureDaemon removed from /Applications. Config preserved at ~/.config/GestureDaemon"

clean:
	@rm -rf $(BUILD_DIR)

disable-logi:
	@./scripts/disable-logi.sh

enable-logi:
	@./scripts/enable-logi.sh

stop-logi: disable-logi
start-logi: enable-logi
