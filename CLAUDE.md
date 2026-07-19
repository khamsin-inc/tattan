# Tattan — プロジェクト指針

macOS native のクリップボード／スニペット管理アプリ。OSS（MIT）で無料公開。

## プロダクト概要

| 項目 | 内容 |
|---|---|
| 名称 | **Tattan**（タッタン — 右⌘二度押しの音） |
| ライセンス | MIT |
| 対応 macOS | 26 Tahoe 以降 |
| アーキテクチャ | Apple Silicon only |
| 言語/UI | Swift + SwiftUI（メニューバー部分は AppKit 併用） |
| 永続化 | SwiftData |
| クラウド同期 | CloudKit |
| ホットキー | KeyboardShortcuts ライブラリ + 修飾キーダブルタップは自前実装 |
| 自動更新 | Sparkle |
| 配布 | khamsin.jp + GitHub Releases + Homebrew Cask |

## 開発ルール

### コミット
- **Conventional Commits**: `feat:` `fix:` `refactor:` `docs:` `test:` `chore:`
- 1 コミット 1 目的
- メッセージは英語推奨（OSS なので国際的に読まれる）

### バージョニング
- **Semantic Versioning**（major.minor.patch）
- ベータは `1.0.0-beta.1` 形式

### コード品質
- **SwiftLint**（`--strict`。CI で強制）
- 警告 0 でビルド通すこと（warnings-as-errors）
- 公開 API には DocC コメント推奨

### テスト
- **Unit Test**: クリップボード監視・スニペット展開・テンプレート変数の各ロジック
- **UI Test**: 主要フロー（ホットキー呼び出し→ペースト、設定変更）

### ファイル名・型名
- Swift 標準: 型は PascalCase、変数・関数は camelCase
- View には `View` サフィックス（例: `SnippetListView`）
- Service クラスには `Service` サフィックス（例: `ClipboardService`）

### コメント方針
- 「何をしているか」より「なぜそうしているか」を書く
- TODO / FIXME には Issue 番号 or 日付を付ける

## ディレクトリ構成

```
tattan/
├── Tattan.xcodeproj/       # XcodeGen 生成（project.yml が正）
├── Tattan/                 # アプリ本体
│   ├── App/                # @main エントリ・AppDelegate・DI コンテナ
│   ├── Models/             # SwiftData モデル
│   ├── Views/              # SwiftUI ビュー
│   ├── Services/           # ClipboardMonitor / SyncCoordinator / HotkeyService など
│   ├── Utilities/          # ヘルパー・拡張
│   └── Resources/          # Assets / Localizable / AppIcon.icon
├── TattanTests/            # Unit Test
├── scripts/                # リリース（署名・公証・DMG・appcast）・アイコン生成
├── samples/                # デモ用サンプルデータ生成
└── .github/workflows/      # CI（lint + build + test）
```

## 実装時の注意

### XcodeGen
- プロジェクトファイルは `project.yml` から生成。**新規ファイル追加時は `xcodegen generate` 必須**

### CloudKit
- 開発コンテナと本番コンテナを分ける（Debug/Release の xcconfig で切替）
- スキーマ変更は破壊的なので慎重に
- 10MB 超のレコードは同期から除外

### Sparkle
- Ed25519 秘密鍵は **絶対にコミットしない**（.gitignore で除外済み）

### 機微情報マスキング
- 表示マスクのみ。実体はそのまま保持してペーストできる仕様

### ホットキー（右 Cmd ダブルタップ）
- `NSEvent.addGlobalMonitorForEvents` でキーイベント監視
- Accessibility 権限が必要 → 初回起動時にユーザーに権限要求 UI を出す

### ローカライズ
- `Localizable.xcstrings` は手動管理（キー追加は JSON 直接編集、indent 2 + `" : "` セパレータの Xcode 形式を維持）
