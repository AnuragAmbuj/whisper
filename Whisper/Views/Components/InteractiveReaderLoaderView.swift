//
//  InteractiveReaderLoaderView.swift
//  Whisper
//
//  Created by Anurag Ambuj on 20/09/26.
//

import Combine
import SwiftUI

struct InteractiveReaderLoaderView: View {
  var bookTitle: String = ""
  var chapterTitle: String = "Opening Chapter..."
  var theme: AppTheme = .default
  var onSkip: (() -> Void)? = nil

  @State private var isFlipping = false
  @State private var pulseScale: CGFloat = 0.95
  @State private var dotCount = 1

  private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

  var body: some View {
    ZStack {
      // Dimmed backdrop with blur
      Color.black.opacity(0.35)
        .ignoresSafeArea()
        .onTapGesture {
          onSkip?()
        }

      VStack(spacing: DS.Spacing.lg) {
        // Animated Book Graphic
        ZStack {
          // Soft ambient backlight glow
          Circle()
            .fill(
              RadialGradient(
                colors: [
                  DS.Colors.accent.opacity(0.35),
                  Color.clear
                ],
                center: .center,
                startRadius: 10,
                endRadius: 75
              )
            )
            .frame(width: 140, height: 140)
            .scaleEffect(pulseScale)
            .animation(
              .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
              value: pulseScale
            )

          // 3D Animated Liquid Book
          HStack(spacing: 0) {
            // Left page (static)
            RoundedRectangle(cornerRadius: 4)
              .fill(theme.textColor.opacity(0.18))
              .frame(width: 32, height: 44)
              .overlay(
                VStack(alignment: .leading, spacing: 4) {
                  ForEach(0..<4) { _ in
                    RoundedRectangle(cornerRadius: 1)
                      .fill(theme.textColor.opacity(0.35))
                      .frame(height: 2)
                  }
                }
                .padding(.horizontal, 4)
              )

            // Book spine divider
            Rectangle()
              .fill(theme.textColor.opacity(0.45))
              .frame(width: 2.5, height: 46)

            // Right page (flipping with 3D perspective)
            ZStack {
              // Static background right page
              RoundedRectangle(cornerRadius: 4)
                .fill(theme.textColor.opacity(0.18))
                .frame(width: 32, height: 44)
                .overlay(
                  VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<4) { _ in
                      RoundedRectangle(cornerRadius: 1)
                        .fill(theme.textColor.opacity(0.35))
                        .frame(height: 2)
                    }
                  }
                  .padding(.horizontal, 4)
                )

              // Dynamic flipping page
              RoundedRectangle(cornerRadius: 4)
                .fill(theme.textColor.opacity(0.28))
                .frame(width: 32, height: 44)
                .overlay(
                  VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<4) { _ in
                      RoundedRectangle(cornerRadius: 1)
                        .fill(theme.textColor.opacity(0.55))
                        .frame(height: 2)
                    }
                  }
                  .padding(.horizontal, 4)
                )
                .rotation3DEffect(
                  .degrees(isFlipping ? -170 : 0),
                  axis: (x: 0, y: 1, z: 0),
                  anchor: .leading,
                  perspective: 0.5
                )
            }
          }
        }
        .frame(height: 80)

        // Informational Text
        VStack(spacing: DS.Spacing.xs) {
          if !bookTitle.isEmpty {
            Text(bookTitle)
              .font(.caption.weight(.medium))
              .foregroundColor(theme.textColor.opacity(0.7))
              .lineLimit(1)
          }

          Text(chapterTitle + String(repeating: ".", count: dotCount))
            .font(.subheadline.weight(.semibold))
            .foregroundColor(theme.textColor)
            .animation(.none, value: dotCount)

          Text("Preparing fluid canvas & typography")
            .font(.caption2)
            .foregroundColor(theme.textColor.opacity(0.6))
        }

        // Interactive "Skip / Show Content" Pill
        Button(action: {
          withAnimation(.easeOut(duration: 0.2)) {
            onSkip?()
          }
        }) {
          HStack(spacing: DS.Spacing.xs) {
            Text("Tap to view now")
              .font(.caption.weight(.medium))
            Image(systemName: "arrow.right.circle.fill")
              .font(.caption)
          }
          .foregroundColor(theme.textColor.opacity(0.85))
          .padding(.horizontal, DS.Spacing.md)
          .padding(.vertical, DS.Spacing.xs)
          .background(theme.textColor.opacity(0.1))
          .cornerRadius(20)
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, DS.Spacing.xxl)
      .padding(.vertical, DS.Spacing.xl)
      .background(.ultraThinMaterial)
      .cornerRadius(24)
      .overlay(
        RoundedRectangle(cornerRadius: 24)
          .stroke(theme.textColor.opacity(0.12), lineWidth: 1)
      )
      .shadow(color: Color.black.opacity(0.2), radius: 24, x: 0, y: 12)
    }
    .onAppear {
      pulseScale = 1.15
      withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
        isFlipping = true
      }
    }
    .onReceive(timer) { _ in
      dotCount = (dotCount % 3) + 1
    }
  }
}
