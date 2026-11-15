import Foundation
import UIKit

/// Which plugins the owner turned on. Kept in the app's settings, so the
/// list follows the owner to every device they use InkPad on... when the
/// app's settings travel with it.
@MainActor
final class PluginStore: ObservableObject {
    static let shared = PluginStore()

    private static let storageKey = "plugins.enabled"

    /// The plugins that are on. Mail and calendars start on, because they
    /// are the ones people reach for.
    @Published private(set) var enabled: Set<String>

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.storageKey) ?? []
        enabled = Set(saved)
    }

    func isEnabled(_ plugin: Plugin) -> Bool {
        enabled.contains(plugin.id)
    }

    /// Turns a plugin on or off.
    func setEnabled(_ on: Bool, for plugin: Plugin) {
        if on {
            enabled.insert(plugin.id)
        } else {
            enabled.remove(plugin.id)
        }
        UserDefaults.standard.set(Array(enabled).sorted(), forKey: Self.storageKey)
    }

    /// The plugins that are on, in the order of the catalogue.
    var enabledPlugins: [Plugin] {
        PluginCatalog.all.filter { isEnabled($0) }
    }

    /// Opens a service on this iPad. The service's own app is used when it
    /// is there; otherwise the website opens.
    static func open(_ link: Plugin.Link) {
        UIApplication.shared.open(link.url, options: [:]) { _ in }
    }
}
