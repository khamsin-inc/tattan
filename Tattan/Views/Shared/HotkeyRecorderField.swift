import AppKit
import Combine
import SwiftUI

/// レコーダー型ショートカット入力欄（P-1）。
/// クリック → 実際に打鍵して登録。通常コンボに加え、修飾キー単体のダブルタップも
/// 同じ欄で記録できる（KeyboardShortcuts 付属レコーダーでは不可能なため自前実装）。
struct HotkeyRecorderField: View {
    let title: String
    let binding: HotkeyBinding?
    let onChange: (HotkeyBinding?) -> Void
    /// 重複割り当ての所有者名を返すチェッカー（nil なら重複なし）
    var duplicateCheck: ((HotkeyBinding) -> String?)?

    @State private var isRecording = false
    @State private var warning: String?
    @State private var eventMonitor: Any?
    @State private var detectors: [UInt16: DoubleTapDetector] = [:]
    @State private var fieldID = UUID()

    /// 録音は常に 1 欄だけ。新しい録音開始を他の欄に知らせて止めさせる
    /// （2 欄同時録音だと 1 回のダブルタップが両方に登録されてしまう）
    private static let willStartRecording = Notification.Name("HotkeyRecorderFieldWillStartRecording")

    var body: some View {
        HStack {
            Text(title)
                .scaledFont(13)
            if let warning {
                Text(warning)
                    .scaledFont(11)
                    .foregroundStyle(.orange)
            }
            Button(action: toggleRecording) {
                Text(isRecording ? String(localized: "Press keys…") : HotkeyService.displayString(for: binding))
                    .scaledFont(13)
                    .frame(minWidth: 130)
            }
            if binding != nil, !isRecording {
                Button {
                    onChange(nil)
                    warning = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .scaledFont(13)
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Remove shortcut"))
            }
            Spacer()
        }
        .onDisappear { stopRecording() }
        .onReceive(NotificationCenter.default.publisher(for: Self.willStartRecording)) { notification in
            if (notification.object as? UUID) != fieldID, isRecording {
                stopRecording()
            }
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        NotificationCenter.default.post(name: Self.willStartRecording, object: fieldID)
        isRecording = true
        warning = nil
        detectors = [:]
        // 録音は自アプリのウィンドウ内 = ローカルモニタで足りる（権限不要）
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            let consumed = MainActor.assumeIsolated {
                handle(event)
            }
            return consumed ? nil : event
        }
    }

    private func stopRecording() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
        isRecording = false
    }

    /// true = イベントを消費した
    private func handle(_ event: NSEvent) -> Bool {
        if event.type == .keyDown {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers.isEmpty {
                switch event.keyCode {
                case 53: // Esc = キャンセル
                    stopRecording()
                    return true
                case 51: // Delete = 割り当て解除
                    onChange(nil)
                    warning = nil
                    stopRecording()
                    return true
                default:
                    return true // 修飾キーなしの単キーは登録対象外（誤爆防止）
                }
            }
            // ⌘ / ⌃ / ⌥ のいずれかを含むコンボのみ受け付ける（⇧単独は IME 等と衝突するため）
            guard modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.option) else {
                return true
            }
            commit(.combo(
                carbonKeyCode: Int(event.keyCode),
                carbonModifiers: CarbonModifierConverter.carbonModifiers(from: modifiers)
            ))
            return true
        }

        // flagsChanged: 全修飾キーの検出器に共通変換（ModifierEventTranslator）で流す。
        // リマッパー（⌘英かな等）が解放イベントの keyCode を書き換える環境にも対応
        for modifier in DoubleTapModifier.allCases {
            guard let input = ModifierEventTranslator.input(
                for: modifier,
                keyCode: event.keyCode,
                rawFlags: event.modifierFlags.rawValue,
                timestamp: event.timestamp
            ) else { continue }
            var detector = detectors[modifier.keyCode] ?? DoubleTapDetector()
            let fired = detector.process(input)
            detectors[modifier.keyCode] = detector
            if fired {
                commit(.doubleTap(modifier))
                break
            }
        }
        return false // 修飾キーイベントは消費しない（システム動作を阻害しない）
    }

    private func commit(_ newBinding: HotkeyBinding) {
        if let owner = duplicateCheck?(newBinding) {
            warning = String(localized: "Also assigned to: \(owner)")
        } else {
            warning = nil
        }
        onChange(newBinding)
        stopRecording()
    }
}
