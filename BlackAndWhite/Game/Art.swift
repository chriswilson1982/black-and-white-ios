import SpriteKit
import UIKit

/// Textures drawn in code. SF Symbols stand in for the Pythonista icon set.
enum Art {
    struct Icon {
        let texture: SKTexture
        let size: CGSize
    }

    /// Pixels per point that textures are drawn at. Set from the game's view before anything is drawn:
    /// an image renderer's default format guesses the scale from UIKit's current traits, which
    /// SpriteKit code doesn't have, and can fall back to 1x (blurry, jagged edges on a 3x screen).
    static var displayScale: CGFloat = 3 {
        didSet {
            guard displayScale != oldValue else { return }
            // Anything drawn at the old scale would be the wrong resolution.
            iconCache = [:]
            fillCache = [:]
            cornerCache = [:]
        }
    }

    /// An image renderer at `displayScale`, with a transparent background.
    private static func renderer(size: CGSize) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = displayScale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    private static var iconCache: [String: Icon] = [:]

    /// An SF Symbol drawn in a solid colour.
    static func icon(_ name: String, color: UIColor, pointSize: CGFloat,
                     weight: UIImage.SymbolWeight = .semibold) -> Icon {
        let key = "\(name)|\(color.cacheKey)|\(Int(pointSize * 10))|\(weight.rawValue)"
        if let cached = iconCache[key] { return cached }

        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let symbol = UIImage(systemName: name, withConfiguration: config)?
            .withTintColor(color, renderingMode: .alwaysOriginal)
        else {
            return Icon(texture: SKTexture(), size: CGSize(width: pointSize, height: pointSize))
        }
        // Drawing the symbol into a bitmap first makes sure the tint colour is kept.
        let image = renderer(size: symbol.size).image { _ in
            symbol.draw(at: .zero)
        }
        let icon = Icon(texture: SKTexture(image: image), size: image.size)
        iconCache[key] = icon
        return icon
    }

    /// The bonus star: a plump five-pointed star with rounded points and inner corners, to match
    /// the rounded squares, filled in `fill` with a fine `outline` (if given) so any star colour
    /// stands out against the square underneath. `pointSize` is the width and height.
    static func star(fill: UIColor, outline: UIColor?, pointSize: CGFloat) -> Icon {
        let key = "star|\(fill.cacheKey)|\(outline?.cacheKey ?? "-")|\(Int(pointSize * 10))"
        if let cached = iconCache[key] { return cached }
        let side = pointSize
        let rounding = side * 0.14
        // A bold outline, about 2 points at grid size.
        let outlineWidth = outline == nil ? 0 : max(1.5, side * 0.065)
        // Leave room for the rounding and outline, which spread out past the star's points.
        let outer = side / 2 - rounding / 2 - outlineWidth
        let path = starPath(centre: CGPoint(x: side / 2, y: side / 2 + outer * 0.06),
                            outer: outer, inner: outer * 0.5)
        path.lineJoinStyle = .round
        let image = renderer(size: CGSize(width: side, height: side)).image { _ in
            // A round-jointed stroke over the fill is what rounds off every corner.
            if let outline = outline {
                outline.setFill()
                outline.setStroke()
                path.lineWidth = rounding + 2 * outlineWidth
                path.fill()
                path.stroke()
            }
            fill.setFill()
            fill.setStroke()
            path.lineWidth = rounding
            path.fill()
            path.stroke()
        }
        let star = Icon(texture: SKTexture(image: image), size: image.size)
        iconCache[key] = star
        return star
    }

    /// A five-pointed star with sharp corners, point upwards (UIKit's top-down coordinates).
    private static func starPath(centre: CGPoint, outer: CGFloat, inner: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        for i in 0..<10 {
            let radius = i.isMultiple(of: 2) ? outer : inner
            let angle = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
            let point = CGPoint(x: centre.x + radius * cos(angle), y: centre.y + radius * sin(angle))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.close()
        return path
    }

    /// White shapes, tinted at runtime with `color` and `colorBlendFactor = 1`.
    static let roundedSquare: SKTexture = shape { rect in
        UIBezierPath(roundedRect: rect, cornerRadius: rect.width * 0.1).fill()
    }

    /// How far a rounded-off corner reaches, as a fraction of the square's side.
    static let cornerFraction: CGFloat = 0.22

    // Corner textures are drawn at exactly the size they appear on screen (at the screen's
    // pixel density), so their curves stay smooth. Shrinking a big texture down makes jagged edges.
    private static var fillCache: [Int: SKTexture] = [:]
    private static var cornerCache: [String: SKTexture] = [:]

    /// Cache key for a size in points, to a hundredth of a point.
    private static func sizeKey(_ side: CGFloat) -> Int { Int((side * 100).rounded()) }

    /// A white square `side` points across with a concave wedge in the bottom-right: the exact
    /// shape cut off a rounded corner of radius `side` (see `square(rounding:side:)`).
    ///
    /// The curve meets the two edges at exactly the same points as the rounded corner, so there
    /// is no step where it joins the straight edges. In between it bulges out by under a point,
    /// overlapping the corner it fills so no background shows along the seam.
    static func fillet(side: CGFloat) -> SKTexture {
        fillet(side: side, half: nil)
    }

    /// Which half of a fillet to draw, split along its diagonal through the corner point:
    /// the half lying along the bottom edge, or along the right edge.
    enum FilletHalf: Int {
        case bottom = 1, right = 2
    }

    /// Half of `fillet(side:)`, for a connector between two squares of different colours,
    /// so each colour reaches exactly halfway.
    static func fillet(side: CGFloat, half: FilletHalf?) -> SKTexture {
        let key = sizeKey(side) * 4 + (half?.rawValue ?? 0)
        if let cached = fillCache[key] { return cached }
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        // The rounded corner is a quarter circle centred on the top-left corner. This arc runs
        // through the same two end points but has its centre pushed out along the diagonal
        // (to -d, -d) and a larger radius, so it sits a little further from the bottom-right
        // in the middle. `mid` is where it crosses the diagonal (the true circle's is side / √2).
        let overlap = min(0.75, side * 0.1)
        let mid = side / 2.squareRoot() - overlap / 2.squareRoot()
        let d = (side * side - 2 * mid * mid) / (4 * mid - 2 * side)
        let radius = 2.squareRoot() * (mid + d)
        let centre = CGPoint(x: -d, y: -d)
        let image = renderer(size: rect.size).image { _ in
            UIColor.white.setFill()
            if let half = half {
                // Keep one side of the diagonal from the top-left to the corner point (bottom-right),
                // plus half a point past it, so the two halves overlap slightly and leave no seam.
                let e: CGFloat = 0.5
                let clip = UIBezierPath()
                switch half {
                case .bottom:
                    clip.move(to: .zero)
                    clip.addLine(to: CGPoint(x: e, y: 0))
                    clip.addLine(to: CGPoint(x: side, y: side - e))
                    clip.addLine(to: CGPoint(x: side, y: side))
                    clip.addLine(to: CGPoint(x: 0, y: side))
                case .right:
                    clip.move(to: .zero)
                    clip.addLine(to: CGPoint(x: side, y: 0))
                    clip.addLine(to: CGPoint(x: side, y: side))
                    clip.addLine(to: CGPoint(x: side - e, y: side))
                    clip.addLine(to: CGPoint(x: 0, y: e))
                }
                clip.close()
                clip.addClip()
            }
            let path = UIBezierPath()
            path.move(to: CGPoint(x: rect.maxX, y: 0))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: 0, y: rect.maxY))
            // From (0, side) round to (side, 0).
            path.addArc(withCenter: centre, radius: radius,
                        startAngle: atan2(side + d, d), endAngle: atan2(d, side + d), clockwise: false)
            path.close()
            path.fill()
        }
        let texture = SKTexture(image: image)
        fillCache[key] = texture
        return texture
    }

    /// A white square `side` points across with only the given corners rounded,
    /// tinted at runtime like `roundedSquare`.
    ///
    /// The corners are true quarter circles, so they match `fillet(side:)` exactly. UIKit's
    /// rounded rectangles use a smoother "continuous" curve that starts further along each
    /// edge, which would leave a step where the fill piece ends.
    static func square(rounding corners: UIRectCorner, side: CGFloat) -> SKTexture {
        let key = "\(corners.rawValue)|\(sizeKey(side))"
        if let cached = cornerCache[key] { return cached }
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        let r = side * cornerFraction
        let w = side
        let image = renderer(size: rect.size).image { _ in
            UIColor.white.setFill()
            // Clockwise from the top-left, in UIKit's top-down coordinates.
            let path = UIBezierPath()
            path.move(to: CGPoint(x: corners.contains(.topLeft) ? r : 0, y: 0))
            if corners.contains(.topRight) {
                path.addLine(to: CGPoint(x: w - r, y: 0))
                path.addArc(withCenter: CGPoint(x: w - r, y: r), radius: r,
                            startAngle: -.pi / 2, endAngle: 0, clockwise: true)
            } else {
                path.addLine(to: CGPoint(x: w, y: 0))
            }
            if corners.contains(.bottomRight) {
                path.addLine(to: CGPoint(x: w, y: w - r))
                path.addArc(withCenter: CGPoint(x: w - r, y: w - r), radius: r,
                            startAngle: 0, endAngle: .pi / 2, clockwise: true)
            } else {
                path.addLine(to: CGPoint(x: w, y: w))
            }
            if corners.contains(.bottomLeft) {
                path.addLine(to: CGPoint(x: r, y: w))
                path.addArc(withCenter: CGPoint(x: r, y: w - r), radius: r,
                            startAngle: .pi / 2, endAngle: .pi, clockwise: true)
            } else {
                path.addLine(to: CGPoint(x: 0, y: w))
            }
            if corners.contains(.topLeft) {
                path.addLine(to: CGPoint(x: 0, y: r))
                path.addArc(withCenter: CGPoint(x: r, y: r), radius: r,
                            startAngle: .pi, endAngle: 3 * .pi / 2, clockwise: true)
            }
            path.close()
            path.fill()
        }
        let texture = SKTexture(image: image)
        cornerCache[key] = texture
        return texture
    }

    static let circle: SKTexture = shape { rect in
        UIBezierPath(ovalIn: rect).fill()
    }

    /// The rounded star in white, for tinted star sparkles.
    static let star: SKTexture = star(fill: .white, outline: nil, pointSize: 40).texture
    static let sparkle: SKTexture = icon("sparkle", color: .white, pointSize: 40).texture

    private static func shape(_ draw: (CGRect) -> Void) -> SKTexture {
        let rect = CGRect(x: 0, y: 0, width: 64, height: 64)
        let image = renderer(size: rect.size).image { _ in
            UIColor.white.setFill()
            draw(rect)
        }
        return SKTexture(image: image)
    }
}

/// Reduce Motion (Settings → Accessibility → Motion). When on, the game swaps movement for fades.
enum Motion {
    static var reduced: Bool { UIAccessibility.isReduceMotionEnabled }
}

extension UIColor {
    /// Mixes towards `other` by `amount` (0 = this colour, 1 = other).
    func blended(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = min(max(amount, 0), 1)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t, alpha: a1 + (a2 - a1) * t)
    }

    var cacheKey: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%.3f,%.3f,%.3f,%.3f", r, g, b, a)
    }
}

extension SKAction {
    func timing(_ mode: SKActionTimingMode) -> SKAction {
        timingMode = mode
        return self
    }
}
