//
//  RoundedCornerShape.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import SwiftUI

struct RectCorner: OptionSet, Sendable {
    let rawValue: Int
    
    nonisolated static let topLeft = RectCorner(rawValue: 1 << 0)
    nonisolated static let topRight = RectCorner(rawValue: 1 << 1)
    nonisolated static let bottomLeft = RectCorner(rawValue: 1 << 2)
    nonisolated static let bottomRight = RectCorner(rawValue: 1 << 3)
    nonisolated static let allCorners: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

struct RoundedCornerShape: Shape {
    var radius: CGFloat
    var corners: RectCorner

    nonisolated func path(in rect: CGRect) -> Path {
        let cornerMask = corners.rawValue
        let hasTopRight = cornerMask & RectCorner.topRight.rawValue != 0
        let hasTopLeft = cornerMask & RectCorner.topLeft.rawValue != 0
        let hasBottomRight = cornerMask & RectCorner.bottomRight.rawValue != 0
        let hasBottomLeft = cornerMask & RectCorner.bottomLeft.rawValue != 0
        
        var path = Path()
        let w = rect.width
        let h = rect.height
        let tr = hasTopRight ? radius : 0
        let tl = hasTopLeft ? radius : 0
        let br = hasBottomRight ? radius : 0
        let bl = hasBottomLeft ? radius : 0
        
        path.move(to: CGPoint(x: tl, y: 0))
        path.addLine(to: CGPoint(x: w - tr, y: 0))
        path.addQuadCurve(to: CGPoint(x: w, y: tr), control: CGPoint(x: w, y: 0))
        path.addLine(to: CGPoint(x: w, y: h - br))
        path.addQuadCurve(to: CGPoint(x: w - br, y: h), control: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: bl, y: h))
        path.addQuadCurve(to: CGPoint(x: 0, y: h - bl), control: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: 0, y: tl))
        path.addQuadCurve(to: CGPoint(x: tl, y: 0), control: CGPoint(x: 0, y: 0))
        
        return path
    }
}
