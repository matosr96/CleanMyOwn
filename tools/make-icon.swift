//
//  make-icon.swift — genera Assets/AppIcon.icns
//
//  Renderiza el icono de CleanMyOwn (squircle con el gradiente de marca +
//  símbolo sparkles) siguiendo la plantilla de macOS: lienzo de 1024 con el
//  squircle de 824 centrado y sombra suave.
//
//  Uso:  swift tools/make-icon.swift   (luego run.sh lo empaqueta)
//

import AppKit

let canvas: CGFloat = 1024
let squircleSize: CGFloat = 824
let inset = (canvas - squircleSize) / 2

let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else {
    fatalError("Sin contexto gráfico")
}

// Sombra del squircle (plantilla macOS)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 36,
              color: NSColor.black.withAlphaComponent(0.35).cgColor)

let squircle = NSBezierPath(
    roundedRect: NSRect(x: inset, y: inset, width: squircleSize, height: squircleSize),
    xRadius: squircleSize * 0.225,
    yRadius: squircleSize * 0.225
)
NSColor(red: 0.40, green: 0.42, blue: 1.0, alpha: 1).setFill()
squircle.fill()
ctx.restoreGState()

// Gradiente de marca (mismo lenguaje que Theme.brandGradient + violeta)
let gradient = NSGradient(colors: [
    NSColor(red: 0.48, green: 0.42, blue: 1.00, alpha: 1),
    NSColor(red: 0.30, green: 0.62, blue: 1.00, alpha: 1),
    NSColor(red: 0.66, green: 0.40, blue: 0.98, alpha: 1)
])!
gradient.draw(in: squircle, angle: -55)

// Brillo superior sutil
let highlight = NSGradient(colors: [
    NSColor.white.withAlphaComponent(0.22),
    NSColor.white.withAlphaComponent(0.0)
])!
highlight.draw(in: squircle, angle: -90)

// Símbolo sparkles en blanco, centrado
let config = NSImage.SymbolConfiguration(pointSize: 430, weight: .bold)
if let symbol = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    // Tintar a blanco: dibujar el símbolo y recomponer encima con sourceAtop
    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus()
    symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)
    NSColor.white.set()
    NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
    tinted.unlockFocus()

    let symbolRect = NSRect(
        x: (canvas - tinted.size.width) / 2,
        y: (canvas - tinted.size.height) / 2,
        width: tinted.size.width,
        height: tinted.size.height
    )
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 22,
                  color: NSColor.black.withAlphaComponent(0.30).cgColor)
    tinted.draw(in: symbolRect)
    ctx.restoreGState()
}

image.unlockFocus()

// Guardar PNG 1024
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("No se pudo serializar el PNG")
}

let outDir = "Assets"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let pngPath = "\(outDir)/AppIcon-1024.png"
try! png.write(to: URL(fileURLWithPath: pngPath))
print("✅ \(pngPath)")
