SWIFTC=swiftc
TARGET=GestureDaemon
BUNDLE_ID=com.user.GestureDaemon
BUILD_DIR=./build
SRC=$(shell find GestureDaemon -name "*.swift")
ENTITLEMENTS=GestureDaemon.entitlements
INSTALL_BIN=/usr/local/bin/$(TARGET)
LAUNCH_AGENT_DIR=$(HOME)/Library/LaunchAgents
AGENT_PLIST=scripts/com.user.gesturedaemon.plist
SDK=$(shell xcrun --show-sdk-path)

.PHONY: all clean build diagnose install uninstall disable-logi enable-logi stop-logi start-logi

all: clean build

build:
	@echo "==> Compiling GestureDaemon (arm64 + x86_64)..."
	@mkdir -p $(BUILD_DIR)/cache
	$(SWIFTC) -O -module-cache-path $(BUILD_DIR)/cache -target arm64-apple-macos13.0 -sdk $(SDK) $(SRC) -o $(BUILD_DIR)/$(TARGET)-arm64
	$(SWIFTC) -O -module-cache-path $(BUILD_DIR)/cache -target x86_64-apple-macos13.0 -sdk $(SDK) $(SRC) -o $(BUILD_DIR)/$(TARGET)-x86_64
	@echo "==> Fusing universal binary..."
	lipo -create -output $(BUILD_DIR)/$(TARGET) $(BUILD_DIR)/$(TARGET)-arm64 $(BUILD_DIR)/$(TARGET)-x86_64
	@echo "==> Code signing (stable identifier: $(BUNDLE_ID))..."
	codesign --force --sign - --identifier "$(BUNDLE_ID)" --entitlements $(ENTITLEMENTS) $(BUILD_DIR)/$(TARGET)
	@echo "==> Build complete: $(BUILD_DIR)/$(TARGET)"

diagnose: build
	@echo "==> Diagnostic mode. Ctrl+C to exit."
	$(BUILD_DIR)/$(TARGET) --diagnostics

# NOTE: run as `make install`, NOT `sudo make install`. sudo is scoped to the
# one line that needs root; everything else (config dir, LaunchAgent) must be
# written and loaded as your own user, not root, or launchctl load registers
# in the wrong session.
install: build
	@echo "==> Installing binary (will prompt for sudo password)..."
	sudo install -m 755 $(BUILD_DIR)/$(TARGET) $(INSTALL_BIN)
	@mkdir -p $(HOME)/.config/GestureDaemon
	@if [ ! -f $(HOME)/.config/GestureDaemon/config.plist ]; then \
		cp GestureDaemon/Configuration/config.plist $(HOME)/.config/GestureDaemon/config.plist; \
		chmod 600 $(HOME)/.config/GestureDaemon/config.plist; \
		echo "==> Default config written to $(HOME)/.config/GestureDaemon/config.plist"; \
	fi
	@mkdir -p $(LAUNCH_AGENT_DIR)
	@cp $(AGENT_PLIST) $(LAUNCH_AGENT_DIR)/
	@launchctl unload $(LAUNCH_AGENT_DIR)/com.user.gesturedaemon.plist 2>/dev/null || true
	launchctl load $(LAUNCH_AGENT_DIR)/com.user.gesturedaemon.plist
	@echo "==> Installed and loaded."

uninstall:
	@launchctl unload $(LAUNCH_AGENT_DIR)/com.user.gesturedaemon.plist 2>/dev/null || true
	@rm -f $(LAUNCH_AGENT_DIR)/com.user.gesturedaemon.plist
	sudo rm -f $(INSTALL_BIN)
	@echo "==> Binary removed. Config preserved at ~/.config/GestureDaemon"

clean:
	@rm -rf $(BUILD_DIR)

disable-logi:
	@./scripts/disable-logi.sh

enable-logi:
	@./scripts/enable-logi.sh

stop-logi: disable-logi
start-logi: enable-logi
