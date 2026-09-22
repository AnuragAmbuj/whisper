//
//  WhisperMarkView.swift
//  Whisper
//
//  Created by Anurag Ambuj on 22/09/26.
//

import SwiftUI

// MARK: - Whisper Mark Bezier Shape

/// Native vector shape of the "Whisper Mark"
/// Triple-entendre:
/// 1. 'W' monogram for Whisper.
/// 2. Alternating soundwave / speech waveform.
/// 3. Sweeping silhouette of an open book's pages.
struct WhisperMarkShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let scaleX = rect.width / 1024.0
    let scaleY = rect.height / 1024.0

    // Coordinates directly derived from the master SVG path
    let startPoint = CGPoint(x: 200.0 * scaleX, y: 238.0 * scaleY)
    let c1 = CGPoint(x: 100.0 * scaleX, y: 538.0 * scaleY)
    let e1 = CGPoint(x: 350.0 * scaleX, y: 788.0 * scaleY)

    let c2 = CGPoint(x: 470.0 * scaleX, y: 538.0 * scaleY)
    let e2 = CGPoint(x: 512.0 * scaleX, y: 388.0 * scaleY)

    let c3 = CGPoint(x: 554.0 * scaleX, y: 538.0 * scaleY)
    let e3 = CGPoint(x: 674.0 * scaleX, y: 788.0 * scaleY)

    let c4 = CGPoint(x: 924.0 * scaleX, y: 538.0 * scaleY)
    let e4 = CGPoint(x: 824.0 * scaleX, y: 238.0 * scaleY)

    path.move(to: startPoint)
    path.addQuadCurve(to: e1, control: c1)
    path.addQuadCurve(to: e2, control: c2)
    path.addQuadCurve(to: e3, control: c3)
    path.addQuadCurve(to: e4, control: c4)

    return path
  }
}

// MARK: - Gradient & Theme Constants

extension WhisperMarkShape {
  /// The signature 4-color tech gradient stops from the Whisper SVG spec
  static let brandGradientStops: [Gradient.Stop] = [
    .init(color: Color(red: 0x42 / 255.0, green: 0x85 / 255.0, blue: 0xF4 / 255.0), location: 0.0),   // Google Blue
    .init(color: Color(red: 0xEA / 255.0, green: 0x43 / 255.0, blue: 0x35 / 255.0), location: 0.33),  // Coral Red
    .init(color: Color(red: 0xFB / 255.0, green: 0xBC / 255.0, blue: 0x05 / 255.0), location: 0.66),  // Amber Yellow
    .init(color: Color(red: 0x34 / 255.0, green: 0xA8 / 255.0, blue: 0x53 / 255.0), location: 1.0)    // Emerald Green
  ]

  /// The signature 4-color tech gradient from the Whisper SVG spec
  static var brandGradient: LinearGradient {
    LinearGradient(
      stops: brandGradientStops,
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }
}

// MARK: - Animated Write-In Mark View

/// Animated vector Whisper Mark that writes itself into existence with smooth easing.
struct WhisperMarkAnimatedView: View {
  var size: CGFloat = 110
  var strokeWidthRatio: CGFloat = 0.1367  // 140 / 1024
  var duration: Double = 1.35
  var autoStart: Bool = true
  var onComplete: (() -> Void)? = nil

  @State private var strokeProgress: CGFloat = 0.0
  @State private var glowOpacity: Double = 0.0
  @State private var scale: CGFloat = 0.96

  var body: some View {
    let lineWidth = max(3.0, size * strokeWidthRatio)

    ZStack {
      // Soft ambient background glow when written
      WhisperMarkShape()
        .stroke(
          WhisperMarkShape.brandGradient,
          style: StrokeStyle(lineWidth: lineWidth * 1.5, lineCap: .round, lineJoin: .round)
        )
        .blur(radius: size * 0.12)
        .opacity(glowOpacity * 0.35)

      // Main stroked ribbon
      WhisperMarkShape()
        .trim(from: 0.0, to: strokeProgress)
        .stroke(
          WhisperMarkShape.brandGradient,
          style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
        .shadow(color: Color.black.opacity(0.12), radius: size * 0.06, y: size * 0.03)
    }
    .frame(width: size, height: size)
    .scaleEffect(scale)
    .onAppear {
      if autoStart {
        startAnimation()
      }
    }
  }

  func startAnimation() {
    strokeProgress = 0.0
    glowOpacity = 0.0
    scale = 0.96

    withAnimation(.easeInOut(duration: duration)) {
      strokeProgress = 1.0
      scale = 1.0
    }

    withAnimation(.easeIn(duration: 0.6).delay(duration * 0.75)) {
      glowOpacity = 1.0
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
      onComplete?()
    }
  }
}

// MARK: - Custom Reusable Loader

/// A continuous animated loading spinner based on the Whisper Mark.
/// Elegantly traces the soundwave/book curve in a fluid continuous wave loop.
struct WhisperMarkLoaderView: View {
  enum Style {
    case wave    // Fluid moving segment looping along the W ribbon
    case pulse   // Writing and erasing rhythmic breath
  }

  var size: CGFloat = 44
  var style: Style = .wave
  var showTrack: Bool = true

  @State private var trimStart: CGFloat = 0.0
  @State private var trimEnd: CGFloat = 0.0
  @State private var isSpinning: Bool = false

  var body: some View {
    let lineWidth = max(2.5, size * 0.1367)

    ZStack {
      // Background subtle track
      if showTrack {
        WhisperMarkShape()
          .stroke(
            Color.primary.opacity(0.08),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
          )
      }

      // Traveling animated gradient wave
      WhisperMarkShape()
        .trim(from: trimStart, to: trimEnd)
        .stroke(
          WhisperMarkShape.brandGradient,
          style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
    }
    .frame(width: size, height: size)
    .onAppear {
      startLoopingAnimation()
    }
  }

  private func startLoopingAnimation() {
    switch style {
    case .wave:
      // Smooth continuous wave: head leads, tail follows
      trimStart = 0.0
      trimEnd = 0.0

      withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
        trimEnd = 1.0
      }

      withAnimation(.easeInOut(duration: 1.0).delay(0.25).repeatForever(autoreverses: true)) {
        trimStart = 0.85
      }

    case .pulse:
      // Breathing write-in and write-out cycle
      trimStart = 0.0
      trimEnd = 0.0
      withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
        trimEnd = 1.0
      }
    }
  }
}

// MARK: - Previews

#Preview("Animated Write-In") {
  VStack(spacing: 40) {
    WhisperMarkAnimatedView(size: 140)

    HStack(spacing: 30) {
      WhisperMarkLoaderView(size: 36, style: .wave)
      WhisperMarkLoaderView(size: 48, style: .pulse)
      WhisperMarkLoaderView(size: 64, style: .wave)
    }
  }
  .padding(50)
  .background(DS.Colors.background)
}
