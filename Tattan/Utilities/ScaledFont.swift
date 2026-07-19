import SwiftUI

/// UI 拡大率（F-7 / N-4）。エディタ・ポップアップのルートで実値（SettingsStore.uiScale）を
/// 流し込み、子孫の `.scaledFont(...)` がこれを掛ける。未注入の場所（例: 設定ウィンドウ内の
/// 共有コンポーネント）では既定 1.0 = 等倍で振る舞う。
private struct UIScaleKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

extension EnvironmentValues {
    var uiScale: Double {
        get { self[UIScaleKey.self] }
        set { self[UIScaleKey.self] = newValue }
    }
}

private struct ScaledFont: ViewModifier {
    @Environment(\.uiScale) private var scale
    let base: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: base * scale, weight: weight, design: design))
    }
}

extension View {
    /// `base` pt のシステムフォントに環境の `uiScale` を掛けて適用する。
    /// Text だけでなく Image(SF Symbol) にも効く（シンボルは font サイズに追従するため、
    /// 文字とアイコンを 1 つの倍率でまとめて拡大できる）。
    func scaledFont(
        _ base: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        modifier(ScaledFont(base: base, weight: weight, design: design))
    }
}
