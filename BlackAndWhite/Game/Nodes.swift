import SpriteKit
import UIKit

/// A label in the system font's rounded design, to match the SwiftUI screens. SpriteKit labels
/// pick fonts by name and the rounded design has no public name, so this draws its text as
/// attributed text instead. `text`, `fontSize` and `fontColor` work as usual.
final class RoundedLabelNode: SKLabelNode {
    var weight: UIFont.Weight = .regular {
        didSet { refresh() }
    }

    private var refreshing = false

    override var text: String? {
        didSet { refresh() }
    }

    override var fontSize: CGFloat {
        didSet { refresh() }
    }

    override var fontColor: UIColor? {
        didSet { refresh() }
    }

    /// Rebuilds the attributed text from the current text, size, weight and colour.
    private func refresh() {
        // Setting the attributed text can touch `text` too; don't come back round.
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        guard let text = text else {
            attributedText = nil
            return
        }
        attributedText = NSAttributedString(string: text, attributes: [
            .font: Self.font(size: fontSize, weight: weight),
            .foregroundColor: fontColor ?? .white,
        ])
    }

    /// The system font in its rounded design.
    static func font(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let system = UIFont.systemFont(ofSize: size, weight: weight)
        return system.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? system
    }
}

/// The colour a square is showing (or is about to show, mid-animation).
struct SquareLook: Equatable {
    var color: UIColor
    var alpha: CGFloat

    var isBlack: Bool { color == .black }
}

/// A square on the game grid.
final class SquareNode: SKSpriteNode {
    let point: GridPoint
    /// Resting position on the grid, used to settle after a shake.
    var home: CGPoint = .zero
    /// The latest colour given to the square. Flips and tints may still be animating towards it.
    private(set) var look = SquareLook(color: .black, alpha: 1)

    /// A curved piece of this square's colour that fills a neighbour's rounded-off corner.
    struct CornerFill: Hashable {
        /// The corner of this square (`UIRectCorner` raw value) at the grid point being filled.
        var corner: UInt
        /// Direction from that grid point into the neighbouring square's corner (x right, y up).
        var dx: Int
        var dy: Int
        /// The whole piece, or just the half along one edge of the corner being filled.
        var half: Half = .whole

        enum Half: Hashable {
            case whole
            /// The half along the corner's horizontal edge (shared with the square above or below it).
            case alongHorizontalEdge
            /// The half along the corner's vertical edge (shared with the square beside it).
            case alongVerticalEdge
        }
    }

    /// How the corners are drawn in the rounded style.
    struct CornerShape: Equatable {
        /// This square's rounded-off corners (`UIRectCorner` raw values).
        var rounded: UInt = 0
        /// Neighbours' rounded-off corners that this square fills with its own colour.
        var fills: Set<CornerFill> = []
    }

    /// Rounded style: squares touch, and each colour island gets rounded corners.
    private let rounded: Bool
    private let side: CGFloat
    private var shape = CornerShape()
    /// Holds the corner fills, so they can be hidden together.
    private let cornerLayer = SKNode()
    private var fillNodes: [CornerFill: SKSpriteNode] = [:]

    enum FlipAxis {
        /// Squashes sideways, like a card turning left to right.
        case vertical
        /// Squashes top to bottom.
        case horizontal
    }

    /// - Parameter rounded: black corners are rounded where they meet other colours; otherwise plain squares.
    init(point: GridPoint, side: CGFloat, rounded: Bool) {
        self.point = point
        self.rounded = rounded
        self.side = side
        if rounded {
            super.init(texture: Art.square(rounding: [], side: side), color: .black,
                       size: CGSize(width: side, height: side))
            colorBlendFactor = 1
            addChild(cornerLayer)
        } else {
            super.init(texture: nil, color: .black, size: CGSize(width: side, height: side))
        }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shows a new colour straight away.
    func setLook(_ newLook: SquareLook) {
        color = newLook.color
        alpha = newLook.alpha
        look = newLook
    }

    /// Redraws the corners. Does nothing if the shape hasn't changed.
    func setCornerShape(_ newShape: CornerShape) {
        guard rounded, newShape != shape else { return }
        shape = newShape
        texture = Art.square(rounding: UIRectCorner(rawValue: newShape.rounded), side: side)

        let r = side * Art.cornerFraction
        fillNodes.values.forEach { $0.isHidden = true }
        for fill in newShape.fills {
            if fillNodes[fill] == nil {
                let left = fill.corner == UIRectCorner.topLeft.rawValue || fill.corner == UIRectCorner.bottomLeft.rawValue
                let top = fill.corner == UIRectCorner.topLeft.rawValue || fill.corner == UIRectCorner.topRight.rawValue
                // The grid point, at this square's corner.
                let point = CGPoint(x: left ? -side / 2 : side / 2, y: top ? side / 2 : -side / 2)
                // The texture's solid corner points down-right (-45°); turn it to face the grid point.
                let rotation = atan2(CGFloat(-fill.dy), CGFloat(-fill.dx)) + .pi / 4
                // Children tint with the parent's colour and share its alpha, so the piece always
                // matches this square exactly, even mid-flip.
                // The texture reaches `bleed` past its straight edges (see `Art.filletBleed`).
                // Anchoring on the centre of the curved r × r piece places and turns it as before.
                let bleed = Art.filletBleed
                let node = SKSpriteNode(texture: Self.fillTexture(fill.half, side: r, rotation: rotation),
                                        color: .white, size: CGSize(width: r + bleed, height: r + bleed))
                // In SpriteKit's bottom-up units: the piece's centre is r/2 from the left and
                // r/2 + bleed from the bottom (the bleed strip runs along the bottom and right).
                node.anchorPoint = CGPoint(x: (r / 2) / (r + bleed), y: (r / 2 + bleed) / (r + bleed))
                node.position = CGPoint(x: point.x + CGFloat(fill.dx) * r / 2, y: point.y + CGFloat(fill.dy) * r / 2)
                node.zRotation = rotation
                // Slightly above the squares, so it overlaps the rounded edge it fills and no seam shows.
                node.zPosition = 0.3
                cornerLayer.addChild(node)
                fillNodes[fill] = node
            }
            fillNodes[fill]?.isHidden = false
        }
        syncFillColor()
    }

    /// The fillet texture for a piece turned by `rotation`. For a half piece, works out which of the
    /// texture's halves (along its bottom or right edge) ends up along the wanted edge once turned.
    private static func fillTexture(_ half: CornerFill.Half, side: CGFloat, rotation: CGFloat) -> SKTexture {
        let textureHalf: Art.FilletHalf
        switch half {
        case .whole:
            return Art.fillet(side: side)
        case .alongHorizontalEdge, .alongVerticalEdge:
            // The texture's bottom edge runs left from the corner point; see where turning sends it.
            let bottomEdgeIsHorizontal = abs(cos(rotation)) > abs(sin(rotation))
            let wantHorizontal = half == .alongHorizontalEdge
            textureHalf = bottomEdgeIsHorizontal == wantHorizontal ? .bottom : .right
        }
        return Art.fillet(side: side, half: textureHalf)
    }

    /// Keeps the corner fills the same colour as the square, including mid-tint.
    /// Called every frame, as tint animations change `color` gradually.
    func syncFillColor() {
        for node in fillNodes.values where !node.isHidden && node.color != color {
            node.color = color
            node.colorBlendFactor = 1
        }
    }

    /// Hides the corner fills, then fades them in once the square has landed.
    func revealCorners(after delay: TimeInterval) {
        cornerLayer.removeAllActions()
        cornerLayer.alpha = 0
        cornerLayer.run(.sequence([.wait(forDuration: delay), .fadeIn(withDuration: 0.15)]))
    }

    /// Hides the corner fills, for a square leaving the grid.
    func hideCorners() {
        cornerLayer.removeAllActions()
        cornerLayer.alpha = 0
    }

    /// Card flip: squash flat, swap colour at the midpoint, then open out again.
    /// `look` is read at the midpoint, so the square always lands on its latest colour.
    func flip(delay: TimeInterval = 0, axis: FlipAxis = .vertical,
              look: @escaping () -> (color: UIColor, alpha: CGFloat)) {
        removeAction(forKey: "flip")
        removeAction(forKey: "tint")
        let swap = SKAction.run { [weak self] in
            let target = look()
            self?.setLook(SquareLook(color: target.color, alpha: target.alpha))
        }
        if Motion.reduced {
            run(.sequence([.wait(forDuration: delay), .fadeAlpha(to: 0.4, duration: 0.07), swap]),
                withKey: "flip")
            return
        }
        let half = 0.09
        let squash: SKAction
        let open: SKAction
        switch axis {
        case .vertical:
            squash = SKAction.scaleX(to: 0.04, duration: half).timing(.easeIn)
            open = SKAction.scaleX(to: 1, duration: half).timing(.easeOut)
        case .horizontal:
            squash = SKAction.scaleY(to: 0.04, duration: half).timing(.easeIn)
            open = SKAction.scaleY(to: 1, duration: half).timing(.easeOut)
        }
        run(.sequence([.wait(forDuration: delay), squash, swap, open, .scale(to: 1, duration: 0)]),
            withKey: "flip")
    }

    /// Gentle colour change without a flip (used for the live path tint).
    /// Skipped while a flip is running, because the flip picks up the latest colour itself.
    func recolor(to newColor: UIColor, alpha newAlpha: CGFloat) {
        guard action(forKey: "flip") == nil else { return }
        removeAction(forKey: "tint")
        alpha = newAlpha
        run(.colorize(with: newColor, colorBlendFactor: colorBlendFactor, duration: 0.18), withKey: "tint")
        look = SquareLook(color: newColor, alpha: newAlpha)
    }

    /// The tapped square: changes colour at once and "stamps" down then springs back.
    func stamp(color newColor: UIColor) {
        removeAction(forKey: "flip")
        removeAction(forKey: "tint")
        setLook(SquareLook(color: newColor, alpha: 1))
        guard !Motion.reduced else { return }
        run(.sequence([
            .scale(to: 0.78, duration: 0.06).timing(.easeOut),
            .scale(to: 1.12, duration: 0.1).timing(.easeOut),
            .scale(to: 1, duration: 0.14).timing(.easeInEaseOut),
        ]), withKey: "flip")
    }

    /// Finishes any flip or tint in progress immediately, so neither can overwrite a colour set next.
    func settle() {
        removeAction(forKey: "flip")
        removeAction(forKey: "tint")
        setScale(1)
    }

    /// Quick side-to-side wobble for a tap that does nothing.
    func shake() {
        removeAction(forKey: "shake")
        position = home
        if Motion.reduced {
            let restAlpha = alpha
            run(.sequence([.fadeAlpha(to: restAlpha * 0.4, duration: 0.06),
                           .fadeAlpha(to: restAlpha, duration: 0.12)]), withKey: "shake")
            return
        }
        let d = max(3, size.width * 0.08)
        run(.sequence([
            .moveBy(x: d, y: 0, duration: 0.04),
            .moveBy(x: -2 * d, y: 0, duration: 0.08),
            .moveBy(x: d * 1.4, y: 0, duration: 0.06),
            .move(to: home, duration: 0.05),
        ]), withKey: "shake")
    }

    /// Little bounce as the path floods through.
    func pop(after delay: TimeInterval) {
        guard !Motion.reduced else { return }
        run(.sequence([.wait(forDuration: delay),
                       .scale(to: 1.15, duration: 0.08).timing(.easeOut),
                       .scale(to: 1, duration: 0.12).timing(.easeIn)]), withKey: "pop")
    }

    /// Gentle throb used while the "flip a single square" power-up is armed.
    func startPulse() {
        guard !Motion.reduced else { return }
        run(.repeatForever(.sequence([
            .scale(to: 0.85, duration: 0.4).timing(.easeInEaseOut),
            .scale(to: 0.95, duration: 0.4).timing(.easeInEaseOut),
        ])), withKey: "pulse")
    }

    func stopPulse() {
        guard action(forKey: "pulse") != nil else { return }
        removeAction(forKey: "pulse")
        setScale(1)
    }
}

/// One of the three power-up buttons at the top of the screen.
final class PowerupNode: SKNode {
    enum Kind: Int, CaseIterable {
        case flipAll, unlock, flipOne

        var symbol: String {
            switch self {
            case .flipAll: return "shuffle"
            case .unlock: return "xmark"
            // A half-black, half-white square, like the squares it flips.
            case .flipOne: return "square.lefthalf.filled"
            }
        }
    }

    enum Style {
        case normal
        /// Armed, shown with a coloured fill.
        case highlighted(UIColor)
        /// Armed, shown inverted (black fill, white icon).
        case inverted
    }

    let kind: Kind
    let size: CGSize
    private let body: SKShapeNode
    private let maxRing: SKShapeNode
    private let icon = SKSpriteNode()
    private let label = RoundedLabelNode()
    private var lastCount: Int?

    init(kind: Kind, size: CGSize, maxColor: UIColor) {
        self.kind = kind
        self.size = size
        // Chunky and well rounded; the "full" ring follows the same curve, 4 points further out.
        let radius = size.height * 0.32
        body = SKShapeNode(rectOf: size, cornerRadius: radius)
        maxRing = SKShapeNode(rectOf: CGSize(width: size.width + 8, height: size.height + 8), cornerRadius: radius + 4)
        super.init()

        body.lineWidth = 2.5
        body.strokeColor = .black
        addChild(body)

        maxRing.lineWidth = 4
        maxRing.strokeColor = maxColor
        maxRing.fillColor = .clear
        maxRing.zPosition = -0.1
        addChild(maxRing)

        icon.position = CGPoint(x: -size.width * 0.2, y: 0)
        icon.zPosition = 0.2
        addChild(icon)

        label.fontSize = size.height * 0.6
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: size.width * 0.24, y: 0)
        label.zPosition = 0.2
        addChild(label)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(count: Int, style: Style) {
        let foreground: UIColor
        switch style {
        case .normal:
            body.fillColor = UIColor(white: 1, alpha: 0.8)
            foreground = .black
        case .highlighted(let fill):
            body.fillColor = fill
            foreground = .black
        case .inverted:
            body.fillColor = .black
            foreground = .white
        }
        let art = Art.icon(kind.symbol, color: foreground, pointSize: size.height * 0.45)
        icon.texture = art.texture
        icon.size = art.size
        label.fontColor = foreground
        label.text = "\(count)"
        if let last = lastCount, last != count, !Motion.reduced {
            // Count changed: the number pops (up for gains, down for spending).
            label.removeAction(forKey: "pop")
            label.setScale(1)
            label.run(.sequence([.scale(to: count > last ? 1.5 : 0.6, duration: 0.08),
                                 .scale(to: 1, duration: 0.15).timing(.easeOut)]), withKey: "pop")
        }
        lastCount = count
        maxRing.isHidden = count < Board.maxPowerups
        body.alpha = count == 0 ? 0.5 : 1
        icon.alpha = count == 0 ? 0.4 : 1
        label.alpha = icon.alpha
    }

    func contains(scenePoint p: CGPoint, slop: CGFloat = 6) -> Bool {
        abs(p.x - position.x) <= size.width / 2 + slop && abs(p.y - position.y) <= size.height / 2 + slop
    }
}

/// The countdown dial in the bottom right, which doubles as the restart / next level button.
/// The coloured disc shows time remaining; a background-coloured wedge grows clockwise over it.
final class TimerNode: SKNode {
    let radius: CGFloat
    private let disc: SKShapeNode
    private let wedge = SKShapeNode()
    private let ring: SKShapeNode
    private let hub: SKShapeNode
    private let fixedHand: SKSpriteNode
    private let movingHand: SKSpriteNode
    private let icon = SKSpriteNode()

    private let normalFill: UIColor
    private let lowFill: UIColor

    init(radius: CGFloat, pathColor: UIColor, lockColor: UIColor, background: UIColor, ringColor: UIColor) {
        self.radius = radius
        normalFill = pathColor
        lowFill = lockColor
        disc = SKShapeNode(circleOfRadius: radius)
        ring = SKShapeNode(circleOfRadius: radius)
        hub = SKShapeNode(circleOfRadius: radius * 0.6)
        let handSize = CGSize(width: max(3, radius * 0.12), height: radius - 1)
        fixedHand = SKSpriteNode(color: .black, size: handSize)
        movingHand = SKSpriteNode(color: .black, size: handSize)
        super.init()

        disc.fillColor = pathColor
        disc.strokeColor = .clear
        disc.zPosition = 0
        addChild(disc)

        wedge.fillColor = background
        wedge.strokeColor = background
        wedge.lineWidth = 1
        wedge.zPosition = 1
        addChild(wedge)

        for hand in [fixedHand, movingHand] {
            hand.anchorPoint = CGPoint(x: 0.5, y: 0)
            hand.zPosition = 2
            addChild(hand)
        }

        ring.fillColor = .clear
        ring.strokeColor = ringColor
        ring.lineWidth = 3
        ring.zPosition = 3
        addChild(ring)

        hub.fillColor = .white
        hub.strokeColor = .black
        hub.lineWidth = 1.5
        hub.zPosition = 4
        addChild(hub)

        icon.zPosition = 5
        addChild(icon)
        setIcon("arrow.clockwise")
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// 0 = full time left, 1 = out of time.
    func setProgress(_ value: CGFloat) {
        let f = min(max(value, 0), 1)
        movingHand.zRotation = -2 * .pi * f
        guard f > 0 else {
            wedge.path = nil
            return
        }
        let r = radius
        let path = CGMutablePath()
        if f >= 1 {
            path.addEllipse(in: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r))
        } else {
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: 0, y: r))
            path.addArc(center: .zero, radius: r, startAngle: .pi / 2,
                        endAngle: .pi / 2 - 2 * .pi * f, clockwise: true)
            path.closeSubpath()
        }
        wedge.path = path
    }

    func setLow(_ low: Bool) {
        disc.fillColor = low ? lowFill : normalFill
    }

    func setHandsVisible(_ visible: Bool) {
        fixedHand.isHidden = !visible
        movingHand.isHidden = !visible
    }

    func setIcon(_ name: String) {
        let art = Art.icon(name, color: .black, pointSize: radius * 0.55, weight: .bold)
        icon.texture = art.texture
        icon.size = art.size
    }

    /// A beat on each second of the final countdown.
    func pulseTick() {
        guard !Motion.reduced else { return }
        removeAction(forKey: "tick")
        setScale(1.12)
        run(.scale(to: 1, duration: 0.3).timing(.easeOut), withKey: "tick")
    }

    func reset() {
        removeAction(forKey: "tick")
        setScale(1)
        setProgress(0)
        setLow(false)
        setHandsVisible(true)
        setIcon("arrow.clockwise")
        for node in [disc, hub, ring] as [SKNode] {
            node.setScale(0.6)
            node.run(.scale(to: 1, duration: 0.3))
        }
    }

    func contains(scenePoint p: CGPoint) -> Bool {
        hypot(p.x - position.x, p.y - position.y) <= radius + 10
    }
}
