//
//  RoundedCornerShape.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import SwiftUI

struct RoundedCornerShape: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        #if os(iOS)
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
        #else
        // Fallback for macOS (or implement pure Path logic)
        // macOS doesn't have UIRectCorner/UIBezierPath the same way.
        // For simplicity on macOS, we'll just round all corners or usage specific logic.
        // But better is to write a pure Path implementation.
        var path = Path()
        
        let w = rect.width
        let h = rect.height
        let tr = corners.contains(.topRight) ? radius : 0
        let tl = corners.contains(.topLeft) ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0
        let bl = corners.contains(.bottomLeft) ? radius : 0
        
        path.move(to: CGPoint(x: w - tr, y: 0))
        path.addLine(to: CGPoint(x: tl, y: 0))
        path.addQuadCurve(to: CGPoint(x: 0, y: tl), control: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: h - bl))
        path.addQuadCurve(to: CGPoint(x: bl, y: h), control: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: w - br, y: h))
        path.addQuadCurve(to: CGPoint(x: w, y: h - br), control: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: w, y: tr))
        path.addQuadCurve(to: CGPoint(x: w - tr, y: 0), control: CGPoint(x: w, y: 0))
        
        return path
        #endif
    }
}

#if os(macOS)
// Polyfill UIRectCorner for macOS
struct UIRectCorner: OptionSet {
    let rawValue: Int
    
    static let topLeft = UIRectCorner(rawValue: 1 << 0)
    static let topRight = UIRectCorner(rawValue: 1 << 1)
    static let bottomLeft = UIRectCorner(rawValue: 1 << 2)
    static let bottomRight = UIRectCorner(rawValue: 1 << 3)
    static let allCorners: UIRectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}
#endif
