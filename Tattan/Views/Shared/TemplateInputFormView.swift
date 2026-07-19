import SwiftUI

/// {{ask}} / {{choose}} の回答フォーム（§9.3）。全フィールドを出現順に 1 枚に並べる
/// （連続ダイアログにしない）。Enter = ペースト続行 / Esc = ペースト中止。
struct TemplateInputFormView: View {
    let fields: [TemplateInputCoordinator.Field]
    let onCommit: ([Int: String]) -> Void
    let onCancel: () -> Void

    @State private var values: [Int: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(fields) { field in
                if let options = field.options {
                    Picker(field.label, selection: binding(for: field)) {
                        ForEach(options, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(field.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("", text: binding(for: field))
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            HStack {
                Spacer()
                Button(String(localized: "Cancel"), role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Paste"), action: { onCommit(values) })
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 380)
        .onAppear {
            for field in fields {
                values[field.id] = field.defaultValue
            }
        }
    }

    private func binding(for field: TemplateInputCoordinator.Field) -> Binding<String> {
        Binding(
            get: { values[field.id] ?? field.defaultValue },
            set: { values[field.id] = $0 }
        )
    }
}
