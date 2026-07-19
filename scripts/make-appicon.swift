#!/usr/bin/env swift
// アプリアイコンのアセット生成。
// 入力: 1024x1024 の全面塗りアートワーク（Canva 等で作成。角丸・マージンなしの正方形）
// 出力: macOS アイコングリッド（1024 キャンバスに 824 角丸ボディ）へマスクした
//       AppIcon.appiconset 一式（全 10 サイズの PNG）
// 使い方: swift scripts/make-appicon.swift <input.png> <AppIcon.appiconset のパス> [ファイル名サフィックス]
// サフィックスは外観バリアント用（例: "_dark" → icon_16_dark.png）。省略時は無印（デフォルト外観）。
// Contents.json は別管理（リポジトリに直接コミット）。

import AppKit

let canvas: CGFloat = 1024
let bodyInset: CGFloat = 100
let bodyCornerRadius: CGFloat = 185

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("usage: swift scripts/make-appicon.swift <input.png> <output-appiconset-dir>")
    exit(1)
}
guard let artwork = NSImage(contentsOfFile: arguments[1]) else {
    print("error: could not read \(arguments[1])")
    exit(1)
}
let outputDirectory = URL(fileURLWithPath: arguments[2], isDirectory: true)
let nameSuffix = arguments.count >= 4 ? arguments[3] : ""
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func makeBitmap(pixels: Int) -> (NSBitmapImageRep, NSGraphicsContext) {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("bitmap context creation failed")
    }
    return (rep, context)
}

func writePNG(_ rep: NSBitmapImageRep, name: String) {
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("png encoding failed")
    }
    let url = outputDirectory.appendingPathComponent(name)
    try! png.write(to: url)
    print("wrote \(url.lastPathComponent)")
}

// 1024 マスター: アートワークを 824 ボディへ縮めて角丸マスク、外周は透明マージン
let (masterRep, masterContext) = makeBitmap(pixels: Int(canvas))
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = masterContext
masterContext.imageInterpolation = .high
let bodyRect = CGRect(x: bodyInset, y: bodyInset,
                      width: canvas - bodyInset * 2, height: canvas - bodyInset * 2)
NSBezierPath(roundedRect: bodyRect, xRadius: bodyCornerRadius, yRadius: bodyCornerRadius).addClip()
artwork.draw(in: bodyRect, from: .zero, operation: .sourceOver, fraction: 1)
masterContext.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

let master = NSImage(size: NSSize(width: canvas, height: canvas))
master.addRepresentation(masterRep)

// 各サイズへ縮小（ファイル名は appiconset/Contents.json と対応）
let variants: [(name: String, pixels: Int)] = [
    ("icon_16\(nameSuffix).png", 16), ("icon_16\(nameSuffix)@2x.png", 32),
    ("icon_32\(nameSuffix).png", 32), ("icon_32\(nameSuffix)@2x.png", 64),
    ("icon_128\(nameSuffix).png", 128), ("icon_128\(nameSuffix)@2x.png", 256),
    ("icon_256\(nameSuffix).png", 256), ("icon_256\(nameSuffix)@2x.png", 512),
    ("icon_512\(nameSuffix).png", 512), ("icon_512\(nameSuffix)@2x.png", 1024),
]

for variant in variants {
    let (rep, context) = makeBitmap(pixels: variant.pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let side = CGFloat(variant.pixels)
    master.draw(in: CGRect(x: 0, y: 0, width: side, height: side),
                from: .zero, operation: .sourceOver, fraction: 1)
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    writePNG(rep, name: variant.name)
}
