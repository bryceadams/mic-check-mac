import AppKit
import SwiftUI

/// Draws the template menu bar icon: a mic capsule that fills with level,
/// red when clipping, with a lock badge when input is locked.
enum MenuBarIcon {
    static func image(level: AudioLevel, locked: Bool, showLevel: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let s: CGFloat = 18.0 / 16.0 // draw on a 16pt grid scaled to 18
            let ctx = NSGraphicsContext.current!.cgContext
            ctx.scaleBy(x: s, y: s)
            ctx.translateBy(x: 0, y: 16)
            ctx.scaleBy(x: 1, y: -1) // flip to top-left origin like the mockup SVG

            let stroke = NSColor.black
            let capsule = CGRect(x: 5.5, y: 1.5, width: 5, height: 8)
            let capsulePath = CGPath(roundedRect: capsule, cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)

            // Level fill inside the capsule, from the bottom.
            if showLevel {
                let fillFrac = CGFloat(min(1, pow(Double(level.rms), 0.5)))
                if fillFrac > 0.02 {
                    ctx.saveGState()
                    ctx.addPath(capsulePath); ctx.clip()
                    let h = capsule.height * fillFrac
                    ctx.setFillColor(level.clipped ? NSColor.systemRed.cgColor : stroke.cgColor)
                    ctx.fill(CGRect(x: capsule.minX, y: capsule.maxY - h, width: capsule.width, height: h))
                    ctx.restoreGState()
                }
            }

            ctx.setStrokeColor(stroke.cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.addPath(capsulePath); ctx.strokePath()
            // Cradle arc
            ctx.addArc(center: CGPoint(x: 8, y: 7.5), radius: 5, startAngle: .pi, endAngle: 0, clockwise: true)
            ctx.strokePath()
            // Stem and base
            ctx.move(to: CGPoint(x: 8, y: 12.5)); ctx.addLine(to: CGPoint(x: 8, y: 14.5))
            ctx.move(to: CGPoint(x: 5.5, y: 14.5)); ctx.addLine(to: CGPoint(x: 10.5, y: 14.5))
            ctx.strokePath()

            if locked {
                ctx.setFillColor(stroke.cgColor)
                ctx.fillEllipse(in: CGRect(x: 9.3, y: 9.3, width: 6.4, height: 6.4))
                // Knock out a tiny lock shape.
                ctx.setBlendMode(.clear)
                ctx.fill(CGRect(x: 11.2, y: 12.2, width: 2.6, height: 2.1))
                ctx.setLineWidth(0.7)
                ctx.addArc(center: CGPoint(x: 12.5, y: 12.2), radius: 0.7, startAngle: .pi, endAngle: 0, clockwise: false)
                ctx.strokePath()
                ctx.setBlendMode(.normal)
            }
            return true
        }
        image.isTemplate = true // lets macOS tint for light/dark menu bars
        return image
    }
}
