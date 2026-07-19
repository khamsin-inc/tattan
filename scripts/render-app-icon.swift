#!/usr/bin/env swift
// アプリアイコンのレンダラー（F-6: モノトーン）。
// AI 生成だと ⌘ の幾何が崩れるため、コードで決定論的に描く（2026-06-13 裁定）。
// デザイン: ⌘ ダブルタップの残像 + 純正アプリ風の縦グラデーション（Ken 指定）。
// 使い方: swift scripts/render-app-icon.swift <出力ディレクトリ>
//   → tattan-icon.png（1024px）と tattan-icon.svg（Canva 等での手調整用）を出力

import AppKit

// MARK: - デザイン定数

let canvas: CGFloat = 1024
// macOS アイコングリッド標準: 1024 キャンバスに 824 角丸ボディ＋透明マージン
let bodyInset: CGFloat = 100
let bodyCornerRadius: CGFloat = 185

// 背景: 上が明るいチャコール（純正ダークアイコンの光の向き）
let backgroundTopHex = "#39393d"
let backgroundBottomHex = "#111113"
// グリフ: 白 → グレーの縦グラデーション
let glyphTopHex = "#ffffff"
let glyphBottomHex = "#aeaeb6"
// 残像: 半透明の単色
let echoHex = "#f5f5f7"
let echoAlpha: CGFloat = 0.24

// 純正アイコンのグリフ比率（ボディの 7 割前後）に合わせる
let glyphPointSize: CGFloat = 600
let echoOffset: CGFloat = 60

func color(_ hex: String, alpha: CGFloat = 1) -> NSColor {
    let value = Int(hex.dropFirst(), radix: 16)!
    return NSColor(
        srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: alpha
    )
}

// MARK: - グリフのアウトライン

/// ⌘ グリフ（U+2318）をシステムフォントからアウトラインパスとして取り出す
func commandGlyphPath(pointSize: CGFloat, weight: NSFont.Weight = .medium) -> CGPath {
    let font = NSFont.systemFont(ofSize: pointSize, weight: weight)
    var characters: [UniChar] = [0x2318]
    var glyphs: [CGGlyph] = [0]
    guard CTFontGetGlyphsForCharacters(font, &characters, &glyphs, 1),
          let cgPath = CTFontCreatePathForGlyph(font, glyphs[0], nil) else {
        fatalError("glyph outline extraction failed")
    }
    return cgPath
}

/// フォント座標系（y 上向き）のパスを、指定中心に置いた y 下向き座標系（SVG / 画像）へ変換
func placedPath(_ path: CGPath, center: CGPoint) -> CGPath {
    let bounds = path.boundingBoxOfPath
    var transform = CGAffineTransform.identity
        .translatedBy(x: center.x - bounds.midX, y: center.y + bounds.midY)
        .scaledBy(x: 1, y: -1)
    return path.copy(using: &transform)!
}

// MARK: - PNG 出力（AppKit 描画）

func renderPNG(to url: URL) {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("bitmap context creation failed")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    // AppKit の描画座標は y 上向きなので、SVG と座標を共有するため上下反転して y 下向きに揃える
    let flip = NSAffineTransform()
    flip.translateX(by: 0, yBy: canvas)
    flip.scaleX(by: 1, yBy: -1)
    flip.concat()

    // 背景ボディ
    let bodyRect = CGRect(x: bodyInset, y: bodyInset,
                          width: canvas - bodyInset * 2, height: canvas - bodyInset * 2)
    let body = NSBezierPath(roundedRect: bodyRect, xRadius: bodyCornerRadius, yRadius: bodyCornerRadius)
    // 座標系が反転しているので「画面上が明るい」= 開始色を y 小側に置く angle 90
    NSGradient(starting: color(backgroundTopHex), ending: color(backgroundBottomHex))?
        .draw(in: body, angle: 90)

    let glyph = commandGlyphPath(pointSize: glyphPointSize)
    let center = CGPoint(x: canvas / 2, y: canvas / 2)

    // 残像（左上 = y 下向き座標では x-, y-）
    let echo = NSBezierPath(cgPath: placedPath(
        glyph, center: CGPoint(x: center.x - echoOffset, y: center.y - echoOffset)))
    color(echoHex, alpha: echoAlpha).setFill()
    echo.fill()

    // 実体（グラデーション）
    let main = NSBezierPath(cgPath: placedPath(glyph, center: center))
    NSGraphicsContext.current?.saveGraphicsState()
    main.addClip()
    NSGradient(starting: color(glyphTopHex), ending: color(glyphBottomHex))?
        .draw(in: main.bounds, angle: 90)
    NSGraphicsContext.current?.restoreGraphicsState()

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("png encoding failed")
    }
    try! png.write(to: url)
    print("wrote \(url.path)")
}

// MARK: - SVG 出力（Canva 等での手調整用）

/// CGPath を SVG の d 属性文字列へ変換（座標は変換済み前提）
func svgPathData(_ path: CGPath) -> String {
    var data = ""
    func point(_ point: CGPoint) -> String {
        String(format: "%.1f %.1f", point.x, point.y)
    }
    path.applyWithBlock { element in
        let points = element.pointee.points
        switch element.pointee.type {
        case .moveToPoint: data += "M \(point(points[0])) "
        case .addLineToPoint: data += "L \(point(points[0])) "
        case .addQuadCurveToPoint: data += "Q \(point(points[0])) \(point(points[1])) "
        case .addCurveToPoint: data += "C \(point(points[0])) \(point(points[1])) \(point(points[2])) "
        case .closeSubpath: data += "Z "
        @unknown default: break
        }
    }
    return data.trimmingCharacters(in: .whitespaces)
}

func renderSVG(to url: URL) {
    let glyph = commandGlyphPath(pointSize: glyphPointSize)
    let center = CGPoint(x: canvas / 2, y: canvas / 2)
    let echoPath = placedPath(glyph, center: CGPoint(x: center.x - echoOffset, y: center.y - echoOffset))
    let mainPath = placedPath(glyph, center: center)
    let bodySize = canvas - bodyInset * 2

    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
      <defs>
        <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="\(backgroundTopHex)"/>
          <stop offset="1" stop-color="\(backgroundBottomHex)"/>
        </linearGradient>
        <linearGradient id="glyph" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="\(glyphTopHex)"/>
          <stop offset="1" stop-color="\(glyphBottomHex)"/>
        </linearGradient>
      </defs>
      <rect x="\(Int(bodyInset))" y="\(Int(bodyInset))" width="\(Int(bodySize))" height="\(Int(bodySize))" \
    rx="\(Int(bodyCornerRadius))" fill="url(#bg)"/>
      <path d="\(svgPathData(echoPath))" fill="\(echoHex)" fill-opacity="\(echoAlpha)"/>
      <path d="\(svgPathData(mainPath))" fill="url(#glyph)"/>
    </svg>
    """
    try! svg.data(using: .utf8)!.write(to: url)
    print("wrote \(url.path)")
}

/// ⌘ グリフ単体の SVG（背景なし）。Canva で部品として使う用。
/// - 単色版: Canva 側で再着色できる
/// - グラデ版: Canva は持ち込み SVG へのグラデ適用ができないため、焼き込んで渡す（色変更は再生成で）
func renderGlyphOnlySVG(to url: URL, gradient: Bool) {
    let glyph = commandGlyphPath(pointSize: glyphPointSize)
    let bounds = glyph.boundingBoxOfPath
    let padding: CGFloat = 8
    let width = Int((bounds.width + padding * 2).rounded(.up))
    let height = Int((bounds.height + padding * 2).rounded(.up))
    let path = placedPath(glyph, center: CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) / 2))

    let defs: String
    let fill: String
    if gradient {
        defs = """

          <defs>
            <linearGradient id="glyph" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0" stop-color="\(glyphTopHex)"/>
              <stop offset="1" stop-color="\(glyphBottomHex)"/>
            </linearGradient>
          </defs>
        """
        fill = "url(#glyph)"
    } else {
        defs = ""
        fill = "#ffffff"
    }

    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="\(height)" viewBox="0 0 \(width) \(height)">\(defs)
      <path d="\(svgPathData(path))" fill="\(fill)"/>
    </svg>
    """
    try! svg.data(using: .utf8)!.write(to: url)
    print("wrote \(url.path)")
}

// MARK: - Icon Composer 用レイヤー PNG（透過背景・フルブリード 1024 キャンバス）

/// .icon（Icon Composer）のレイヤーは全面 1024 キャンバスに直接置かれ、角丸マスクは
/// システム側が行う。appiconset 用（824 ボディ + 余白）と違いフルブリード基準なので、
/// グリフサイズとオフセットをボディ比率ぶん拡大して描く。
func renderLayerPNG(to url: URL, echoOnly: Bool) {
    let fullBleedScale = canvas / (canvas - bodyInset * 2)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("bitmap context creation failed")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let flip = NSAffineTransform()
    flip.translateX(by: 0, yBy: canvas)
    flip.scaleX(by: 1, yBy: -1)
    flip.concat()

    let glyph = commandGlyphPath(pointSize: glyphPointSize * fullBleedScale)
    let center = CGPoint(x: canvas / 2, y: canvas / 2)
    if echoOnly {
        let offset = echoOffset * fullBleedScale
        let echo = NSBezierPath(cgPath: placedPath(
            glyph, center: CGPoint(x: center.x - offset, y: center.y - offset)))
        color(echoHex, alpha: echoAlpha).setFill()
        echo.fill()
    } else {
        let main = NSBezierPath(cgPath: placedPath(glyph, center: center))
        NSGraphicsContext.current?.saveGraphicsState()
        main.addClip()
        NSGradient(starting: color(glyphTopHex), ending: color(glyphBottomHex))?
            .draw(in: main.bounds, angle: 90)
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("png encoding failed")
    }
    try! png.write(to: url)
    print("wrote \(url.path)")
}

// MARK: - エントリポイント

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    print("usage: swift scripts/render-app-icon.swift <output-dir>")
    exit(1)
}
let outputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

renderPNG(to: outputDirectory.appendingPathComponent("tattan-icon.png"))
renderSVG(to: outputDirectory.appendingPathComponent("tattan-icon.svg"))
renderGlyphOnlySVG(to: outputDirectory.appendingPathComponent("tattan-command.svg"), gradient: false)
renderGlyphOnlySVG(to: outputDirectory.appendingPathComponent("tattan-command-gradient.svg"), gradient: true)
renderLayerPNG(to: outputDirectory.appendingPathComponent("tattan-layer-glyph.png"), echoOnly: false)
renderLayerPNG(to: outputDirectory.appendingPathComponent("tattan-layer-echo.png"), echoOnly: true)
