import AppKit
import KeyboardShortcuts
import Observation
import os

/// ホットキー登録の唯一の窓口（§8.4）。
/// - 通常コンボ → KeyboardShortcuts（Carbon ベース・権限不要）
/// - 修飾キーダブルタップ → NSEvent モニタ + DoubleTapDetector（Accessibility 必要）
/// スニペット個別ホットキーの真実の源は `Snippet.hotkeyData`（同期される）。
@MainActor
@Observable
final class HotkeyService {

    enum Slot: String, CaseIterable {
        case unified
        case historyOnly
        case snippetsOnly

        var defaultsKey: String { "hotkey.slot.\(rawValue)" }
        var shortcutName: KeyboardShortcuts.Name { KeyboardShortcuts.Name("slot.\(rawValue)") }

        var popupMode: PopupMode {
            switch self {
            case .unified: .unified
            case .historyOnly: .historyOnly
            case .snippetsOnly: .snippetsOnly
            }
        }

        var title: String {
            switch self {
            case .unified: String(localized: "Open popup (history + snippets)")
            case .historyOnly: String(localized: "Open history popup")
            case .snippetsOnly: String(localized: "Open snippets popup")
            }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let snippets: SnippetService
    @ObservationIgnored private let permissions: PermissionService
    @ObservationIgnored private let logger = Logger(subsystem: "jp.khamsin.tattan", category: "hotkey")

    @ObservationIgnored var onPopupTrigger: ((PopupMode) -> Void)?
    @ObservationIgnored var onSnippetTrigger: ((UUID) -> Void)?

    private struct DoubleTapEntry {
        var detector: DoubleTapDetector
        let action: () -> Void
    }

    @ObservationIgnored private var doubleTapEntries: [UInt16: DoubleTapEntry] = [:]
    @ObservationIgnored private var registeredHandlerNames: Set<String> = []
    /// 前回 applyAll でコンボ登録したスニペット別 Name。削除されたスニペットの
    /// ショートカットが登録されたまま残り、キーをグローバルに吸い続けるのを防ぐ
    /// （2026-07-02 レビュー指摘 #3）
    @ObservationIgnored private var appliedSnippetNames: Set<String> = []
    @ObservationIgnored private var globalMonitors: [Any] = []
    @ObservationIgnored private var localMonitor: Any?

    /// 設定画面の注意表示用（ダブルタップは Accessibility が無いと効かない §8.2）
    var isDoubleTapAvailable: Bool { permissions.isAccessibilityTrusted }

    init(defaults: UserDefaults = .standard, snippets: SnippetService, permissions: PermissionService) {
        self.defaults = defaults
        self.snippets = snippets
        self.permissions = permissions
    }

    func start() {
        installMonitors()
        applyAll()
        snippets.onSnippetsChanged = { [weak self] in
            self?.applyAll()
        }
    }

    // MARK: - バインディングの保存・取得

    /// 「未設定（キーなし）」と「明示的にクリア（空 Data）」を区別する。
    /// 未設定の unified スロットだけ既定値 = 右⌘ダブルタップ（F-3）
    func binding(for slot: Slot) -> HotkeyBinding? {
        if let data = defaults.data(forKey: slot.defaultsKey) {
            return data.isEmpty ? nil : HotkeyBinding.decode(data)
        }
        return slot == .unified ? .doubleTap(.rightCommand) : nil
    }

    func setBinding(_ binding: HotkeyBinding?, for slot: Slot) {
        defaults.set(binding?.encoded ?? Data(), forKey: slot.defaultsKey)
        applyAll()
    }

    func setSnippetBinding(_ binding: HotkeyBinding?, for snippet: Snippet) {
        snippet.hotkeyData = binding?.encoded
        snippets.touchUpdated(snippet) // 保存 + onSnippetsChanged → applyAll
    }

    /// P-1: 重複割り当ての所有者名（無ければ nil）
    func duplicateOwner(
        of binding: HotkeyBinding,
        excludingSlot: Slot? = nil,
        excludingSnippet: UUID? = nil
    ) -> String? {
        for slot in Slot.allCases where slot != excludingSlot {
            if self.binding(for: slot) == binding { return slot.title }
        }
        for snippet in snippets.fetchSnippets() where snippet.uuid != excludingSnippet {
            if HotkeyBinding.decode(snippet.hotkeyData) == binding {
                return snippet.title.isEmpty ? String(localized: "Untitled snippet") : snippet.title
            }
        }
        return nil
    }

    static func displayString(for binding: HotkeyBinding?) -> String {
        switch binding {
        case .combo(let keyCode, let modifiers):
            KeyboardShortcuts.Shortcut(carbonKeyCode: keyCode, carbonModifiers: modifiers).description
        case .doubleTap(let modifier):
            modifier.displayName
        case nil:
            String(localized: "Not set")
        }
    }

    // MARK: - 登録

    func applyAll() {
        var entries: [UInt16: DoubleTapEntry] = [:]

        for slot in Slot.allCases {
            let mode = slot.popupMode
            registerHandlerIfNeeded(slot.shortcutName) { [weak self] in
                self?.onPopupTrigger?(mode)
            }
            switch binding(for: slot) {
            case .combo(let keyCode, let modifiers):
                KeyboardShortcuts.setShortcut(
                    KeyboardShortcuts.Shortcut(carbonKeyCode: keyCode, carbonModifiers: modifiers),
                    for: slot.shortcutName
                )
            case .doubleTap(let modifier):
                KeyboardShortcuts.setShortcut(nil, for: slot.shortcutName)
                entries[modifier.keyCode] = DoubleTapEntry(detector: DoubleTapDetector()) { [weak self] in
                    self?.onPopupTrigger?(mode)
                }
            case nil:
                KeyboardShortcuts.setShortcut(nil, for: slot.shortcutName)
            }
        }

        var currentSnippetNames: Set<String> = []
        for snippet in snippets.fetchSnippets() {
            let uuid = snippet.uuid
            let name = KeyboardShortcuts.Name("snippet.\(uuid.uuidString)")
            currentSnippetNames.insert(name.rawValue)
            registerHandlerIfNeeded(name) { [weak self] in
                self?.onSnippetTrigger?(uuid)
            }
            switch HotkeyBinding.decode(snippet.hotkeyData) {
            case .combo(let keyCode, let modifiers):
                KeyboardShortcuts.setShortcut(
                    KeyboardShortcuts.Shortcut(carbonKeyCode: keyCode, carbonModifiers: modifiers),
                    for: name
                )
            case .doubleTap(let modifier):
                KeyboardShortcuts.setShortcut(nil, for: name)
                entries[modifier.keyCode] = DoubleTapEntry(detector: DoubleTapDetector()) { [weak self] in
                    self?.onSnippetTrigger?(uuid)
                }
            case nil:
                KeyboardShortcuts.setShortcut(nil, for: name)
            }
        }

        // 削除されたスニペットのコンボ登録を解除する（Carbon 登録と UserDefaults 永続化の両方が消える）
        for stale in appliedSnippetNames.subtracting(currentSnippetNames) {
            KeyboardShortcuts.setShortcut(nil, for: KeyboardShortcuts.Name(stale))
        }
        appliedSnippetNames = currentSnippetNames

        doubleTapEntries = entries
    }

    /// KeyboardShortcuts.onKeyDown はハンドラが蓄積するため、Name ごとに 1 回だけ登録する
    private func registerHandlerIfNeeded(_ name: KeyboardShortcuts.Name, _ handler: @escaping () -> Void) {
        guard !registeredHandlerNames.contains(name.rawValue) else { return }
        registeredHandlerNames.insert(name.rawValue)
        KeyboardShortcuts.onKeyDown(for: name, action: handler)
    }

    // MARK: - ダブルタップ用イベントモニタ

    private func installMonitors() {
        guard globalMonitors.isEmpty else { return }

        // グローバルモニタは Accessibility 未許可だとイベントが届かないだけで害は無い。
        // 許可後の取り直しが要らないよう最初から張っておく
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags
            let timestamp = event.timestamp
            Task { @MainActor [weak self] in
                self?.handleFlagsChanged(keyCode: keyCode, flags: flags, timestamp: timestamp)
            }
        }) {
            globalMonitors.append(monitor)
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { event in
            let rawFlags = event.modifierFlags.rawValue
            Task { @MainActor [weak self] in
                self?.handleKeyDown(rawFlags: rawFlags)
            }
        }) {
            globalMonitors.append(monitor)
        }
        // 自アプリが前面のときはローカルモニタで同じロジックに流す
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags
            let timestamp = event.timestamp
            let isKeyDown = event.type == .keyDown
            MainActor.assumeIsolated {
                if isKeyDown {
                    self?.handleKeyDown(rawFlags: flags.rawValue)
                } else {
                    self?.handleFlagsChanged(keyCode: keyCode, flags: flags, timestamp: timestamp)
                }
            }
            return event
        }
    }

    private func handleFlagsChanged(keyCode: UInt16, flags: NSEvent.ModifierFlags, timestamp: TimeInterval) {
        guard !doubleTapEntries.isEmpty else { return }

        for code in Array(doubleTapEntries.keys) {
            guard var entry = doubleTapEntries[code],
                  let target = DoubleTapModifier.from(keyCode: code),
                  let input = ModifierEventTranslator.input(
                      for: target, keyCode: keyCode, rawFlags: flags.rawValue, timestamp: timestamp
                  ) else { continue }
            let fired = entry.detector.process(input)
            doubleTapEntries[code] = entry
            if fired {
                entry.action()
            }
        }
    }

    /// キー押下による「コンボ利用」キャンセルは、監視中の修飾キーが押されたままの
    /// 入力（⌘C 等）に限定する。リマッパー（⌘英かな等）は ⌘ 空打ちのたびに修飾なしの
    /// かな/英数キー押下を合成するため、無条件にキャンセルするとダブルタップが永遠に
    /// 成立しない（2026-06-12 Ken 実機ログで確認）
    private func handleKeyDown(rawFlags: UInt) {
        for code in Array(doubleTapEntries.keys) {
            guard var entry = doubleTapEntries[code],
                  let target = DoubleTapModifier.from(keyCode: code),
                  rawFlags & target.classFlagMask != 0 else { continue }
            _ = entry.detector.process(.interruption)
            doubleTapEntries[code] = entry
        }
    }

}

/// NSEvent の修飾キーを Carbon 形式へ変換（レコーダー用）
enum CarbonModifierConverter {
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var result = 0
        if flags.contains(.command) { result |= 256 }  // cmdKey
        if flags.contains(.shift) { result |= 512 }    // shiftKey
        if flags.contains(.option) { result |= 2048 }  // optionKey
        if flags.contains(.control) { result |= 4096 } // controlKey
        return result
    }
}
