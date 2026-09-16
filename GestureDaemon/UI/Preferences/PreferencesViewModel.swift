import SwiftUI
import Combine

public final class PreferencesViewModel: ObservableObject {
    @Published public var config: AppConfig
    @Published public var saveStatusMessage: String? = nil
    @Published public var selectedAppBundleId: String? = nil

    private var cancellables = Set<AnyCancellable>()
    private var isUpdatingFromExternalNotification = false

    public init() {
        self.config = ConfigManager.shared.activeConfig
        setupSubscriptions()
    }

    private func setupSubscriptions() {
        NotificationCenter.default.publisher(for: ConfigManager.configDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                if let updated = notification.object as? AppConfig, updated != self.config {
                    self.isUpdatingFromExternalNotification = true
                    self.config = updated
                    self.isUpdatingFromExternalNotification = false
                    self.showTemporaryStatus("Synced from config.plist")
                }
            }
            .store(in: &cancellables)

        // Auto-save debounced when config changes
        $config
            .dropFirst()
            .debounce(for: .milliseconds(350), scheduler: DispatchQueue.main)
            .sink { [weak self] newConfig in
                guard let self = self else { return }
                if !self.isUpdatingFromExternalNotification {
                    self.save(newConfig)
                }
            }
            .store(in: &cancellables)
    }

    public func save(_ newConfig: AppConfig) {
        do {
            try ConfigManager.shared.saveConfiguration(newConfig)
            showTemporaryStatus("✓ Settings saved")
        } catch {
            showTemporaryStatus("⚠️ Error saving: \(error.localizedDescription)")
        }
    }

    public func resetToDefaults() {
        let defaults = ConfigManager.fallbackDefaultConfig()
        self.config = defaults
        save(defaults)
        showTemporaryStatus("✓ Reset to defaults")
    }

    public func openConfigFileInEditor() {
        let url = ConfigManager.shared.configURL
        if !FileManager.default.fileExists(atPath: url.path) {
            ConfigManager.shared.loadConfiguration()
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Per-App Profiles Management

    public func addApplicationProfile(bundleId: String) {
        var apps = config.applications ?? [:]
        if apps[bundleId] == nil {
            apps[bundleId] = AppProfile()
            config.applications = apps
            selectedAppBundleId = bundleId
        }
    }

    public func removeApplicationProfile(bundleId: String) {
        var apps = config.applications ?? [:]
        apps.removeValue(forKey: bundleId)
        config.applications = apps.isEmpty ? nil : apps
        if selectedAppBundleId == bundleId {
            selectedAppBundleId = config.applications?.keys.sorted().first
        }
    }

    public func setAppAction(bundleId: String, slot: ActionSlot, action: ActionDefinition?) {
        guard var apps = config.applications, var profile = apps[bundleId] else { return }
        profile.setAction(action, for: slot)
        apps[bundleId] = profile
        config.applications = apps
    }

    private func showTemporaryStatus(_ message: String) {
        withAnimation {
            self.saveStatusMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            withAnimation {
                if self?.saveStatusMessage == message {
                    self?.saveStatusMessage = nil
                }
            }
        }
    }
}

