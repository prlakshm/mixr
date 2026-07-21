import SwiftUI

protocol PartyModeTraceableShape: InsettableShape {
    func startPoint(in rect: CGRect) -> CGPoint
}

struct PartyModeClockwiseRoundedRectangle: PartyModeTraceableShape {
    let cornerRadius: CGFloat
    private var insetAmount: CGFloat = 0

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
    }

    private init(cornerRadius: CGFloat, insetAmount: CGFloat) {
        self.cornerRadius = cornerRadius
        self.insetAmount = insetAmount
    }

    func path(in rect: CGRect) -> Path {
        let bounds = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = resolvedRadius(in: bounds)
        var path = Path()

        path.move(to: CGPoint(x: bounds.minX + radius, y: bounds.minY))
        path.addLine(to: CGPoint(x: bounds.maxX - radius, y: bounds.minY))
        path.addArc(
            tangent1End: CGPoint(x: bounds.maxX, y: bounds.minY),
            tangent2End: CGPoint(x: bounds.maxX, y: bounds.minY + radius),
            radius: radius
        )
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY - radius))
        path.addArc(
            tangent1End: CGPoint(x: bounds.maxX, y: bounds.maxY),
            tangent2End: CGPoint(x: bounds.maxX - radius, y: bounds.maxY),
            radius: radius
        )
        path.addLine(to: CGPoint(x: bounds.minX + radius, y: bounds.maxY))
        path.addArc(
            tangent1End: CGPoint(x: bounds.minX, y: bounds.maxY),
            tangent2End: CGPoint(x: bounds.minX, y: bounds.maxY - radius),
            radius: radius
        )
        path.addLine(to: CGPoint(x: bounds.minX, y: bounds.minY + radius))
        path.addArc(
            tangent1End: CGPoint(x: bounds.minX, y: bounds.minY),
            tangent2End: CGPoint(x: bounds.minX + radius, y: bounds.minY),
            radius: radius
        )
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> PartyModeClockwiseRoundedRectangle {
        PartyModeClockwiseRoundedRectangle(
            cornerRadius: cornerRadius,
            insetAmount: insetAmount + amount
        )
    }

    func startPoint(in rect: CGRect) -> CGPoint {
        let bounds = rect.insetBy(dx: insetAmount, dy: insetAmount)
        return CGPoint(x: bounds.minX + resolvedRadius(in: bounds), y: bounds.minY)
    }

    private func resolvedRadius(in rect: CGRect) -> CGFloat {
        min(max(0, cornerRadius - insetAmount), min(rect.width, rect.height) / 2)
    }
}

struct PartyModeClockwiseCircle: PartyModeTraceableShape {
    private var insetAmount: CGFloat = 0
    private let startAngle = Angle.degrees(-120)

    func path(in rect: CGRect) -> Path {
        let bounds = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = min(bounds.width, bounds.height) / 2
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: .degrees(240),
            clockwise: false
        )
        return path
    }

    func inset(by amount: CGFloat) -> PartyModeClockwiseCircle {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func startPoint(in rect: CGRect) -> CGPoint {
        let bounds = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = min(bounds.width, bounds.height) / 2
        let radians = CGFloat(startAngle.radians)
        return CGPoint(
            x: bounds.midX + cos(radians) * radius,
            y: bounds.midY + sin(radians) * radius
        )
    }
}

struct PartyModeTrimSegment: Identifiable, Sendable {
    let id: Int
    let from: CGFloat
    let to: CGFloat
}

enum PartyModeTrimSegments {
    static func wrapped(from rawStart: CGFloat, to rawEnd: CGFloat) -> [PartyModeTrimSegment] {
        let length = max(0, rawEnd - rawStart)
        guard length > 0 else { return [] }
        guard length < 1 else {
            return [PartyModeTrimSegment(id: 0, from: 0, to: 1)]
        }

        var start = rawStart
        var end = rawEnd
        while start < 0 {
            start += 1
            end += 1
        }
        while start >= 1 {
            start -= 1
            end -= 1
        }

        if end <= 1 {
            return [PartyModeTrimSegment(id: 0, from: start, to: end)]
        }

        return [
            PartyModeTrimSegment(id: 0, from: start, to: 1),
            PartyModeTrimSegment(id: 1, from: 0, to: end - 1),
        ]
    }
}
