//
//  AudiobookPlayerView.swift
//  Whisper
//
//  Created by Anurag Ambuj on 28/09/26.
//

import SwiftUI
import AVFoundation
#if os(iOS)
import AVKit
#elseif os(macOS)
import AVKit
#endif

struct AudiobookPlayerView: View {
    let book: Book
    @Bindable var viewModel: ReaderViewModel
    @Binding var showControls: Bool
    var onDismiss: (() -> Void)? = nil
    
    @State private var player = AudiobookPlayerService.shared
    @State private var isScrubbing: Bool = false
    @State private var scrubTime: Double = 0.0
    @State private var showChaptersSheet: Bool = false
    @State private var showSleepTimerSheet: Bool = false
    
    // Waveform envelope data
    @State private var waveAmplitudes: [CGFloat] = []
    
    private let barCount: Int = 44
    private let playbackRates: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    private let sleepTimerOptions: [Int] = [5, 15, 30, 45, 60]
    
    var body: some View {
        GeometryReader { geometry in
            let availW = geometry.size.width
            let availH = geometry.size.height
            let isLandscape = availW > availH && availH < 560
            
            ZStack {
                // Deep Ambient Background with Radiant Bloom
                ambientBackground
                
                if isLandscape {
                    landscapeContent(availW: availW, availH: availH)
                } else {
                    portraitContent(availW: availW, availH: availH)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                setupPlayer()
                setupWaveform()
            }
            .onDisappear {
                player.pause()
                viewModel.flushReadingProgressToCloud()
            }
            .sheet(isPresented: $showChaptersSheet) {
                chaptersSheet
            }
            .sheet(isPresented: $showSleepTimerSheet) {
                sleepTimerSheet
            }
        }
    }
    
    // MARK: - Setup
    
    private func setupPlayer() {
        player.loadBook(book) { progress, location in
            viewModel.updateProgress(progress)
            viewModel.updateLocation(location)
        }
    }
    
    private func setupWaveform() {
        let seed = abs(book.title.hashValue) % 1000
        var amplitudes: [CGFloat] = []
        for i in 0..<barCount {
            let progress = Double(i) / Double(barCount)
            let envelope = sin(progress * .pi)
            let w1 = sin(Double(i) * 0.52 + Double(seed) * 0.15)
            let w2 = cos(Double(i) * 0.98 + Double(seed) * 0.28)
            let w3 = sin(Double(i) * 1.75) * 0.35
            let raw = (w1 * 0.45 + w2 * 0.35 + w3 * 0.2 + 1.0) * 0.5
            let combined = max(0.18, min(1.0, envelope * 0.35 + raw * 0.65))
            amplitudes.append(CGFloat(combined))
        }
        self.waveAmplitudes = amplitudes
    }
    
    private func triggerHaptic() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
    }
    
    // MARK: - Ambient Background
    
    private var ambientBackground: some View {
        ZStack {
            // Obsidian background coherent with Whisper Dark theme
            Color(red: 0.08, green: 0.08, blue: 0.10)
                .ignoresSafeArea()
            
            // Atmospheric warm amber & deep twilight radiant glow bloom
            RadialGradient(
                colors: [
                    Color(red: 0.98, green: 0.52, blue: 0.18).opacity(player.isPlaying ? 0.30 : 0.15),
                    Color(red: 0.10, green: 0.22, blue: 0.28).opacity(player.isPlaying ? 0.22 : 0.10),
                    Color.clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 260
            )
            .frame(width: 380, height: 380)
            .offset(y: -50)
            .blur(radius: 60)
            .animation(.easeInOut(duration: 1.5), value: player.isPlaying)
        }
    }
    
    // MARK: - Portrait Content
    
    private func portraitContent(availW: CGFloat, availH: CGFloat) -> some View {
        // Proportional sizing guarantees zero overflow across all devices
        let coverSize = max(130, min(availW * 0.52, availH * 0.27, 240))
        
        return VStack(spacing: 0) {
            #if os(iOS)
            // Clearance for ReaderView standard top navigation HUD
            Spacer()
                .frame(height: 54)
            #elseif os(macOS)
            Spacer()
                .frame(height: 20)
            #endif
            
            Spacer(minLength: 6)
            
            // 1. Cover Art Card
            coverArtView(size: coverSize)
                .frame(width: coverSize, height: coverSize)
            
            Spacer(minLength: 10)
            
            // 2. Title & Metadata
            titleAndMetadataView(availW: availW)
                .padding(.horizontal, DS.Spacing.md)
            
            Spacer(minLength: 10)
            
            // 3. Interactive Glowing Waveform Scrubber
            waveformScrubberView
                .padding(.horizontal, DS.Spacing.lg)
            
            Spacer(minLength: 12)
            
            // 4. Primary Playback Controls (15s Back, Play/Pause, 15s Forward)
            mainPlaybackControlsView
                .padding(.horizontal, DS.Spacing.lg)
            
            Spacer(minLength: 12)
            
            // 5. Floating Bottom Dock (Speed, Chapters, Sleep, AirPlay)
            bottomDockCapsule
                .padding(.bottom, DS.Spacing.md)
        }
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Landscape Content
    
    private func landscapeContent(availW: CGFloat, availH: CGFloat) -> some View {
        let coverSize = max(110, min(availH * 0.60, availW * 0.32, 210))
        
        return HStack(spacing: DS.Spacing.xl) {
            // Left Column: Cover & Title
            VStack(spacing: DS.Spacing.xs) {
                Spacer(minLength: 4)
                coverArtView(size: coverSize)
                    .frame(width: coverSize, height: coverSize)
                
                titleAndMetadataView(availW: availW * 0.4)
                Spacer(minLength: 4)
            }
            .frame(maxWidth: .infinity)
            
            // Right Column: Waveform, Play Controls, and Dock
            VStack(spacing: DS.Spacing.sm) {
                Spacer(minLength: 4)
                waveformScrubberView
                    .padding(.horizontal, DS.Spacing.sm)
                
                mainPlaybackControlsView
                
                bottomDockCapsule
                Spacer(minLength: 4)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.top, 40)
        .padding(.bottom, DS.Spacing.xs)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Cover Art View
    
    private func coverArtView(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
                .shadow(
                    color: Color.black.opacity(player.isPlaying ? 0.55 : 0.32),
                    radius: player.isPlaying ? 22 : 12,
                    x: 0,
                    y: player.isPlaying ? 10 : 6
                )
            
            if !book.coverImageName.isEmpty {
                CachedAsyncImage(
                    imageName: book.coverImageName,
                    placeholder: {
                        ProgressView()
                    },
                    fallback: {
                        coverFallbackView(size: size)
                    }
                )
                .aspectRatio(1.0, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                coverFallbackView(size: size)
            }
        }
        .scaleEffect(player.isPlaying ? 1.015 : 0.985)
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: player.isPlaying)
    }
    
    private func coverFallbackView(size: CGFloat) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "headphones")
                .font(.system(size: size * 0.28, weight: .light))
                .foregroundColor(Color(red: 0.96, green: 0.46, blue: 0.18))
            
            Text(book.title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 10)
        }
    }
    
    // MARK: - Title & Metadata View
    
    private func titleAndMetadataView(availW: CGFloat) -> some View {
        VStack(spacing: 3) {
            Text(book.title.uppercased())
                .font(.system(size: min(17, max(13, availW * 0.046)), weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .tracking(0.4)
            
            Text(book.author.isEmpty ? "Unknown Author" : book.author)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(Color.white.opacity(0.75))
                .lineLimit(1)
            
            Text(currentChapterSubtitle)
                .font(.system(size: 11.5, weight: .regular))
                .foregroundColor(Color.white.opacity(0.48))
                .lineLimit(1)
        }
    }
    
    private var currentChapterSubtitle: String {
        if player.chapters.indices.contains(player.currentChapterIndex) {
            return player.chapters[player.currentChapterIndex].title
        }
        return "Audiobook"
    }
    
    // MARK: - Interactive Soundwave Scrubber
    
    private var waveformScrubberView: some View {
        GeometryReader { waveGeo in
            let totalWidth = waveGeo.size.width
            let current = isScrubbing ? scrubTime : player.currentTime
            let safeDuration = max(1.0, player.duration)
            let progress = max(0.0, min(1.0, current / safeDuration))
            let hasHours = player.duration >= 3600
            
            VStack(spacing: 6) {
                // Waveform Bars with Timeline Pulse Animation
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !player.isPlaying)) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let phase = (time * 3.5).truncatingRemainder(dividingBy: .pi * 2)
                    
                    HStack(spacing: 2.5) {
                        ForEach(0..<barCount, id: \.self) { index in
                            let barProgress = Double(index) / Double(max(1, barCount - 1))
                            let isPlayed = barProgress <= progress
                            
                            let baseAmp = waveAmplitudes.indices.contains(index) ? waveAmplitudes[index] : 0.5
                            let liveMod = (player.isPlaying && isPlayed) ? (sin(phase + Double(index) * 0.52) * 0.14) : 0.0
                            let normalizedHeight = max(0.14, min(1.0, baseAmp + CGFloat(liveMod)))
                            let barHeight = normalizedHeight * 36.0
                            
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(
                                    isPlayed
                                        ? AnyShapeStyle(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 1.0, green: 0.70, blue: 0.30),
                                                    Color(red: 0.96, green: 0.44, blue: 0.16)
                                                ],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        : AnyShapeStyle(Color.white.opacity(0.18))
                                )
                                .frame(maxWidth: .infinity)
                                .frame(height: barHeight)
                                .shadow(
                                    color: isPlayed ? Color(red: 0.96, green: 0.44, blue: 0.16).opacity(0.3) : .clear,
                                    radius: 2,
                                    x: 0,
                                    y: 0
                                )
                        }
                    }
                    .frame(height: 38, alignment: .center)
                }
                
                // Track line with Glowing Thumb
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 2.5)
                    
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.65, blue: 0.25),
                                    Color(red: 0.96, green: 0.44, blue: 0.16)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, totalWidth * CGFloat(progress)), height: 2.5)
                    
                    Circle()
                        .fill(Color.white)
                        .frame(width: 8.5, height: 8.5)
                        .shadow(color: Color(red: 0.96, green: 0.44, blue: 0.16).opacity(0.75), radius: 3, x: 0, y: 0)
                        .offset(x: max(0, min(totalWidth - 8.5, totalWidth * CGFloat(progress) - 4.25)))
                }
                .frame(height: 10)
                
                // Timestamps (Elapsed & Remaining)
                HStack {
                    Text(AudiobookPlayerService.formatTimeDisplay(current, forceHours: hasHours))
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.65))
                    
                    Spacer()
                    
                    let remaining = max(0.0, player.duration - current)
                    Text("-\(AudiobookPlayerService.formatTimeDisplay(remaining, forceHours: hasHours))")
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.65))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isScrubbing = true
                        let clampedX = max(0, min(totalWidth, value.location.x))
                        let percent = Double(clampedX / totalWidth)
                        scrubTime = percent * safeDuration
                    }
                    .onEnded { value in
                        let clampedX = max(0, min(totalWidth, value.location.x))
                        let percent = Double(clampedX / totalWidth)
                        let finalTime = percent * safeDuration
                        player.seek(to: finalTime)
                        viewModel.updateLocation(Int(finalTime))
                        viewModel.updateProgress(finalTime / safeDuration)
                        viewModel.flushReadingProgressToCloud()
                        triggerHaptic()
                        isScrubbing = false
                    }
            )
        }
        .frame(height: 68)
    }
    
    // MARK: - Main Playback Controls
    
    private var mainPlaybackControlsView: some View {
        HStack(spacing: 30) {
            // Skip 15s Backward
            Button(action: {
                player.skipBackward(15)
                triggerHaptic()
            }) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Skip backward 15 seconds")
            
            // Primary Radiant Orange Play / Pause Button
            Button(action: {
                player.togglePlayPause()
                viewModel.flushReadingProgressToCloud()
                triggerHaptic()
            }) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.54, blue: 0.22),
                                    Color(red: 0.93, green: 0.38, blue: 0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 66, height: 66)
                        .shadow(
                            color: Color(red: 0.93, green: 0.38, blue: 0.12).opacity(0.42),
                            radius: 14,
                            x: 0,
                            y: 5
                        )
                    
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                        .offset(x: player.isPlaying ? 0 : 2)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            
            // Skip 15s Forward
            Button(action: {
                player.skipForward(15)
                triggerHaptic()
            }) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "goforward.15")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Skip forward 15 seconds")
        }
    }
    
    // MARK: - Bottom Dock Capsule
    
    private var bottomDockCapsule: some View {
        HStack(spacing: 12) {
            // Speed Pill
            Menu {
                ForEach(playbackRates, id: \.self) { rate in
                    Button(action: {
                        player.setPlaybackRate(rate)
                        triggerHaptic()
                    }) {
                        HStack {
                            Text(String(format: "%.2fx", rate))
                            if player.playbackRate == rate {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(String(format: "%.1fx", player.playbackRate))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.96, green: 0.46, blue: 0.18).opacity(player.playbackRate != 1.0 ? 0.9 : 0.25))
                            .overlay(
                                Capsule().stroke(Color(red: 0.96, green: 0.46, blue: 0.18).opacity(0.6), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            
            // Chapters Drawer Button
            Button(action: {
                showChaptersSheet = true
                triggerHaptic()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Chapters")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(Color.white.opacity(0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Chapters")
            
            // Sleep Timer Pill Button
            Button(action: {
                showSleepTimerSheet = true
                triggerHaptic()
            }) {
                ZStack {
                    Capsule()
                        .fill(player.sleepTimerRemaining != nil ? Color.white : Color.white.opacity(0.12))
                        .frame(width: 42, height: 28)
                    
                    Image(systemName: "moon.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(
                            player.sleepTimerRemaining != nil
                                ? Color(red: 0.1, green: 0.1, blue: 0.12)
                                : .white
                        )
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sleep Timer")
            
            // AirPlay Route Picker
            AirRoutePickerView()
                .frame(width: 28, height: 28)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.06))
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Chapters Sheet
    
    private var chaptersSheet: some View {
        NavigationStack {
            List {
                ForEach(player.chapters) { chapter in
                    Button(action: {
                        player.jumpToChapter(chapter)
                        viewModel.updateLocation(Int(chapter.startTime))
                        viewModel.updateProgress(chapter.startTime / max(1.0, player.duration))
                        viewModel.flushReadingProgressToCloud()
                        triggerHaptic()
                        showChaptersSheet = false
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(chapter.title)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("Starts at \(chapter.formattedStartTime)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if player.currentTime >= chapter.startTime &&
                               player.currentTime < (chapter.startTime + chapter.duration) {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundColor(Color(red: 0.96, green: 0.46, blue: 0.18))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Chapters")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showChaptersSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Sleep Timer Sheet
    
    private var sleepTimerSheet: some View {
        NavigationStack {
            List {
                Button(action: {
                    player.setSleepTimer(minutes: nil)
                    triggerHaptic()
                    showSleepTimerSheet = false
                }) {
                    HStack {
                        Text("Off")
                        Spacer()
                        if player.sleepTimerRemaining == nil {
                            Image(systemName: "checkmark")
                                .foregroundColor(Color(red: 0.96, green: 0.46, blue: 0.18))
                        }
                    }
                }
                
                ForEach(sleepTimerOptions, id: \.self) { mins in
                    Button(action: {
                        player.setSleepTimer(minutes: mins)
                        triggerHaptic()
                        showSleepTimerSheet = false
                    }) {
                        HStack {
                            Text("\(mins) minutes")
                            Spacer()
                            if let remaining = player.sleepTimerRemaining, Int(remaining / 60) == mins {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Color(red: 0.96, green: 0.46, blue: 0.18))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sleep Timer")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cancel") { showSleepTimerSheet = false }
                }
            }
        }
        .presentationDetents([.height(320)])
    }
}

// MARK: - AirPlay Route Picker Representable

#if os(iOS)
struct AirRoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = UIColor(red: 0.96, green: 0.46, blue: 0.18, alpha: 1.0)
        picker.prioritizesVideoDevices = false
        return picker
    }
    
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#elseif os(macOS)
struct AirRoutePickerView: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        return picker
    }
    
    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}
#endif
