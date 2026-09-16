import SwiftUI

@main
struct VKTurnProxyApp: App {
    init() {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        SharedLogger.shared.log("[App] K&C Shield launched (build \(build))")

        UplinkPace.resetToProductionDefaultOnce { SharedLogger.shared.log("[App] \($0)") }
        UplinkSynth.clearStaleValueOnce { SharedLogger.shared.log("[App] \($0)") }

        _ = ServerStore.shared

        if #available(iOS 16.2, *) {
            Task { @MainActor in
                LiveActivityActionRouter.shared.handler = { action in
                    await LiveActivityController.shared.handle(action)
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            KCShieldRootView()
                .onOpenURL { url in
                    let scheme = url.scheme?.lowercased()
                    if scheme == "vkturnproxy" || scheme == "wdtt" || scheme == "freeturn" || scheme == "csqtt" {
                        ConnectionLinkInbox.shared.deliver(url)
                    }
                }
                .background(KeyboardDismisser())
        }
    }
}
