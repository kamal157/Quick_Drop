import AppKit

// Where the radial arc/fan opens from. The window docks to that edge/corner of
// the screen and the tiles fan out toward the screen interior.
enum ArcOrigin: String, CaseIterable {
    case right, left, top, bottom
    case topRight, topLeft, bottomRight, bottomLeft

    static let `default`: ArcOrigin = .right

    static func from(_ raw: String?) -> ArcOrigin {
        guard let raw, let value = ArcOrigin(rawValue: raw) else { return .default }
        return value
    }

    var label: String {
        switch self {
        case .right: return "Right"
        case .left: return "Left"
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .topRight: return "Top-Right"
        case .topLeft: return "Top-Left"
        case .bottomRight: return "Bottom-Right"
        case .bottomLeft: return "Bottom-Left"
        }
    }

    /// SF Symbol arrow pointing toward the edge the arc opens from.
    var arrowSymbol: String {
        switch self {
        case .right: return "arrow.right"
        case .left: return "arrow.left"
        case .top: return "arrow.up"
        case .bottom: return "arrow.down"
        case .topRight: return "arrow.up.right"
        case .topLeft: return "arrow.up.left"
        case .bottomRight: return "arrow.down.right"
        case .bottomLeft: return "arrow.down.left"
        }
    }

    /// The palette window's frame within a screen's visibleFrame.
    func windowFrame(in vf: NSRect) -> NSRect {
        let edge: CGFloat = 580     // depth for edge origins (room for the semicircle bulge)
        let corner: CGFloat = 600   // square region for corner origins
        switch self {
        case .right:  return NSRect(x: vf.maxX - edge, y: vf.minY, width: edge, height: vf.height)
        case .left:   return NSRect(x: vf.minX, y: vf.minY, width: edge, height: vf.height)
        case .top:    return NSRect(x: vf.minX, y: vf.maxY - edge, width: vf.width, height: edge)
        case .bottom: return NSRect(x: vf.minX, y: vf.minY, width: vf.width, height: edge)
        case .topRight:    return NSRect(x: vf.maxX - corner, y: vf.maxY - corner, width: corner, height: corner)
        case .topLeft:     return NSRect(x: vf.minX, y: vf.maxY - corner, width: corner, height: corner)
        case .bottomRight: return NSRect(x: vf.maxX - corner, y: vf.minY, width: corner, height: corner)
        case .bottomLeft:  return NSRect(x: vf.minX, y: vf.minY, width: corner, height: corner)
        }
    }

    /// The point (in the view's bounds) where the fan converges.
    func anchor(in bounds: NSRect) -> NSPoint {
        let m: CGFloat = 46
        switch self {
        case .right:  return NSPoint(x: bounds.maxX - m, y: bounds.midY)
        case .left:   return NSPoint(x: bounds.minX + m, y: bounds.midY)
        case .top:    return NSPoint(x: bounds.midX, y: bounds.maxY - m)
        case .bottom: return NSPoint(x: bounds.midX, y: bounds.minY + m)
        case .topRight:    return NSPoint(x: bounds.maxX - m, y: bounds.maxY - m)
        case .topLeft:     return NSPoint(x: bounds.minX + m, y: bounds.maxY - m)
        case .bottomRight: return NSPoint(x: bounds.maxX - m, y: bounds.minY + m)
        case .bottomLeft:  return NSPoint(x: bounds.minX + m, y: bounds.minY + m)
        }
    }

    /// Mid-angle (degrees, math convention) of the fan, pointing into the screen.
    var midAngleDegrees: CGFloat {
        switch self {
        case .right: return 180
        case .left: return 0
        case .top: return 270
        case .bottom: return 90
        case .topRight: return 225
        case .topLeft: return 315
        case .bottomRight: return 135
        case .bottomLeft: return 45
        }
    }

    func radius(in bounds: NSRect) -> CGFloat {
        // Edge fans are clean semicircles. The radius is capped so the half-disc
        // stays a tidy, contained shape (rather than stretching across a tall or
        // wide display) while never exceeding what the window can show.
        let edgeCap: CGFloat = 320
        let cornerCap: CGFloat = 340
        switch self {
        case .right, .left:   return min(bounds.height / 2 - 56, bounds.width - 90, edgeCap)
        case .top, .bottom:   return min(bounds.width / 2 - 56, bounds.height - 90, edgeCap)
        default:              return min(min(bounds.width, bounds.height) * 0.72, cornerCap)  // corner quarter-fan
        }
    }

    var isCorner: Bool {
        switch self {
        case .topRight, .topLeft, .bottomRight, .bottomLeft: return true
        default: return false
        }
    }
}
