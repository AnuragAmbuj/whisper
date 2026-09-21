//
//  PinchToZoomModifier.swift
//  Whisper
//
//  Created by Anurag Ambuj on 19/09/26.
//

import SwiftUI

public struct ZoomMetrics {
    public static func clampScale(_ scale: CGFloat, minScale: CGFloat = 1.0, maxScale: CGFloat = 4.0) -> CGFloat {
        max(minScale, min(scale, maxScale))
    }
    
    public static func clampOffset(_ offset: CGSize, scale: CGFloat, containerSize: CGSize) -> CGSize {
        guard scale > 1.0 else { return .zero }
        let maxOffsetX = max(0, (containerSize.width * (scale - 1)) / 2)
        let maxOffsetY = max(0, (containerSize.height * (scale - 1)) / 2)
        
        let clampedX = min(max(offset.width, -maxOffsetX), maxOffsetX)
        let clampedY = min(max(offset.height, -maxOffsetY), maxOffsetY)
        return CGSize(width: clampedX, height: clampedY)
    }
}

public struct PinchToZoomModifier: ViewModifier {
    public var minScale: CGFloat
    public var maxScale: CGFloat
    public var doubleTapScale: CGFloat
    
    @State private var currentScale: CGFloat = 1.0
    @State private var steadyScale: CGFloat = 1.0
    
    @State private var currentOffset: CGSize = .zero
    @State private var steadyOffset: CGSize = .zero
    
    public init(minScale: CGFloat = 1.0, maxScale: CGFloat = 4.0, doubleTapScale: CGFloat = 2.2) {
        self.minScale = minScale
        self.maxScale = maxScale
        self.doubleTapScale = doubleTapScale
    }
    
    private var effectiveScale: CGFloat {
        max(0.75, min(steadyScale * currentScale, maxScale * 1.5))
    }
    
    private var effectiveOffset: CGSize {
        CGSize(
            width: steadyOffset.width + currentOffset.width,
            height: steadyOffset.height + currentOffset.height
        )
    }
    
    public func body(content: Content) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            content
                .frame(width: size.width, height: size.height)
                .scaleEffect(effectiveScale)
                .offset(effectiveOffset)
                .contentShape(Rectangle())
                .gesture(
                    MagnificationGesture()
                        .onChanged { delta in
                            currentScale = delta
                        }
                        .onEnded { delta in
                            let target = steadyScale * delta
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                if target <= (minScale + 0.05) {
                                    steadyScale = minScale
                                    steadyOffset = .zero
                                } else if target >= maxScale {
                                    steadyScale = maxScale
                                    steadyOffset = ZoomMetrics.clampOffset(steadyOffset, scale: maxScale, containerSize: size)
                                } else {
                                    steadyScale = target
                                    steadyOffset = ZoomMetrics.clampOffset(steadyOffset, scale: target, containerSize: size)
                                }
                                currentScale = 1.0
                            }
                        }
                )
                .simultaneousGesture(
                    steadyScale > 1.01 ?
                    DragGesture()
                        .onChanged { value in
                            currentOffset = value.translation
                        }
                        .onEnded { value in
                            let proposed = CGSize(
                                width: steadyOffset.width + value.translation.width,
                                height: steadyOffset.height + value.translation.height
                            )
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                steadyOffset = ZoomMetrics.clampOffset(proposed, scale: steadyScale, containerSize: size)
                                currentOffset = .zero
                            }
                        }
                    : nil
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        if steadyScale > 1.05 {
                            steadyScale = 1.0
                            steadyOffset = .zero
                        } else {
                            steadyScale = doubleTapScale
                            steadyOffset = .zero
                        }
                    }
                }
        }
    }
}

extension View {
    public func pinchToZoom(
        minScale: CGFloat = 1.0,
        maxScale: CGFloat = 4.0,
        doubleTapScale: CGFloat = 2.2
    ) -> some View {
        self.modifier(PinchToZoomModifier(minScale: minScale, maxScale: maxScale, doubleTapScale: doubleTapScale))
    }
}
