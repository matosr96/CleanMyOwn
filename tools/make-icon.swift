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

// SweepGlyph — la MISMA geometría que UI/Components/BrandMark.swift
// (swoosh orbital + eco + punto cometa). El contexto de NSImage tiene la
// Y hacia ARRIBA; el Canvas de SwiftUI hacia abajo, así que los ángulos
// van negados para que el dibujo coincida visualmente.
let glyphR: CGFloat = canvas * 0.255            // "radio" del glifo
let center = CGPoint(x: canvas / 2, y: canvas / 2)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 22,
              color: NSColor.black.withAlphaComponent(0.30).cgColor)
ctx.setStrokeColor(NSColor.white.cgColor)
ctx.setLineCap(.round)

// Arco principal: en pantalla va de -30° a 195° (y-abajo) → negar en y-arriba
ctx.setLineWidth(glyphR * 0.30)
ctx.addArc(center: center, radius: glyphR * 0.80,
           startAngle: CGFloat(30 * Double.pi / 180),
           endAngle: CGFloat(-195 * Double.pi / 180),
           clockwise: true)
ctx.strokePath()

// Eco interior (115°→215° en pantalla)
ctx.setLineWidth(glyphR * 0.18)
ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.55).cgColor)
ctx.addArc(center: center, radius: glyphR * 0.38,
           startAngle: CGFloat(-115 * Double.pi / 180),
           endAngle: CGFloat(-215 * Double.pi / 180),
           clockwise: true)
ctx.strokePath()

// Punto cometa (-62° en pantalla → +62° aquí)
let dotAngle = CGFloat(62 * Double.pi / 180)
let dotCenter = CGPoint(x: center.x + cos(dotAngle) * glyphR * 0.80,
                        y: center.y + sin(dotAngle) * glyphR * 0.80)
let dotR = glyphR * 0.17
ctx.setFillColor(NSColor.white.cgColor)
ctx.fillEllipse(in: CGRect(x: dotCenter.x - dotR, y: dotCenter.y - dotR,
                           width: dotR * 2, height: dotR * 2))
ctx.restoreGState()

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
