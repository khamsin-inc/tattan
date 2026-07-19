import Foundation
import Observation
import ServiceManagement

/// ログイン時自動起動（H-1: 既定 ON）。SMAppService ベース。
@MainActor
@Observable
final class LaunchAtLoginService {
    private(set) var isEnabled: Bool

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // 失敗時は実状態を再読込して UI と齟齬を残さない
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    /// 初回起動時に既定 ON（H-1）を一度だけ適用する。
    /// Debug ビルドでは適用しない — DerivedData のビルド成果物がログイン項目に
    /// 居座ると開発機で実害があるため。
    func applyDefaultIfNeeded(defaults: UserDefaults = .standard) {
        #if !DEBUG
        let key = "didApplyDefaultLaunchAtLogin"
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        setEnabled(true)
        #endif
    }
}
