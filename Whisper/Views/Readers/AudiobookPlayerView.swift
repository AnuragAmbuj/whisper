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
    
    @Environment(\.dismiss) private var environmentDismiss
    @State private var player = AudiobookPlayerService.shared
    @State private var isScrubbing: Bool = false
    @State private var scrubTime: Double = 0.0
    @State private var showChaptersSheet: Bool = false
    @State private var showSleepTimerSheet: Bool = false
    @State private var showOptionsSheet: Bool = false
    
    // Waveform envelope data
    @State private var waveAmplitudes: [CGFloat] = []
    
    private let barCount: Int = 48
    private let playbackRates: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    private let sleepTimerOptions: [Int] = [5, 15, 30, 45, 60]
    
    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            
            ZStack {
                // Ambient Atmospheric Backdrop
                ambientBackground
                
                VStack(spacing: 0) {
                    // Top Navigation Bar (< Library ... Options)
                    topNavigationBar
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.xs)
                    
                    if isLandscape {
                        landscapeContent(geometry: geometry)
                    } else {
                        portraitContent(geometry: geometry)
                    }
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
        // Generate a deterministic, realistic voice waveform profile for this book
        let seed = abs(book.title.hashValue) % 1000
        var amplitudes: [CGFloat] = []
        for i in 0..<barCount {
            let progress = Double(i) / Double(barCount)
            let envelope = sin(progress * .pi)
            let w1 = sin(Double(i) * 0.48 + Double(seed) * 0.15)
            let w2 = cos(Double(i) * 0.95 + Double(seed) * 0.3)
            let w3 = sin(Double(i) * 1.8) * 0.4
            let raw = (w1 * 0.45 + w2 * 0.35 + w3 * 0.2 + 1.0) * 0.5
            let combined = max(0.18, min(1.0, envelope * 0.32 + raw * 0.68))
            amplitudes.append(CGFloat(combined))
        }
        self.waveAmplitudes = amplitudes
    }
    
    private func dismissPlayer() {
        if let onDismiss = onDismiss {
            onDismiss()
        } else {
            environmentDismiss()
        }
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
            // Deep obsidian background
            Color(red: 0.07, green: 0.08, blue: 0.09)
                .ignoresSafeArea()
            
            // Atmospheric warm amber & deep teal radiant glow bloom
            ZStack {
                RadialGradient(
                    colors: [
                        Color(red: 0.96, green: 0.45, blue: 0.15).opacity(player.isPlaying ? 0.32 : 0.18),
                        Color(red: 0.08, green: 0.25, blue: 0.32).opacity(player.isPlaying ? 0.28 : 0.14),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 30,
                    endRadius: 280
                )
                .frame(width: 420, height: 420)
                .offset(y: -40)
                .blur(radius: 65)
                .animation(.easeInOut(duration: 1.5), value: player.isPlaying)
            }
        }
    }
    
    // MARK: - Top Navigation Bar
    
    private var topNavigationBar: some View {
        HStack {
            Button(action: { dismissPlayer() }) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Library")
                        .font(.system(size: 17, weight: .regular))
                }
                .foregroundColor(.white)
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Return to Library")
            
            Spacer()
            
            Menu {
                Button(action: { showChaptersSheet = true }) {
                    Label("Chapters & Tracklist", systemImage: "list.bullet")
                }
                Button(action: {
                    viewModel.toggleBookmark()
                    triggerHaptic()
                }) {
                    Label(
                        viewModel.isBookmarked ? "Remove Bookmark" : "Bookmark Position",
                        systemImage: viewModel.isBookmarked ? "bookmark.fill" : "bookmark"
                    )
                }
                Button(action: { showSleepTimerSheet = true }) {
                    Label("Sleep Timer", systemImage: "moon.zzz")
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Options")
                        .font(.system(size: 17, weight: .regular))
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20, weight: .regular))
                }
                .foregroundColor(.white)
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Audiobook Options")
        }
    }
    
    // MARK: - Portrait Content
    
    private func portraitContent(geometry: GeometryProxy) -> some View {
        let coverSize = min(geometry.size.width - 96, 270)
        
        return VStack(spacing: 0) {
            Spacer(minLength: 16)
            
            // Cover Art Frame
            coverArtView(size: coverSize)
                .frame(width: coverSize, height: coverSize)
            
            Spacer(minLength: 20)
            
            // Title & Author & Chapter Meta
            titleAndMetadataView
                .padding(.horizontal, DS.Spacing.lg)
            
            Spacer(minLength: 24)
            
            // Interactive Glowing Waveform Scrubber
            waveformScrubberView
                .padding(.horizontal, DS.Spacing.xl)
            
            Spacer(minLength: 28)
            
            // Main Playback Controls (Skip 15, Play/Pause, Skip 15)
            mainPlaybackControlsView
                .padding(.horizontal, DS.Spacing.lg)
            
            Spacer(minLength: 24)
            
            // Bottom Dock Capsule (Speed, Chapters, Sleep, AirPlay)
            bottomDockCapsule
                .padding(.bottom, DS.Spacing.xl)
        }
        .frame(maxWidth: DS.Layout.maxContentWidth)
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Landscape Content
    
    private func landscapeContent(geometry: GeometryProxy) -> some View {
        HStack(spacing: DS.Spacing.xxl) {
            // Left Column: Cover Art
            VStack {
                Spacer()
                coverArtView(size: min(geometry.size.height - 120, 240))
                Spacer()
            }
            .frame(maxWidth: .infinity)
            
            // Right Column: Controls
            VStack(spacing: DS.Spacing.md) {
                Spacer()
                titleAndMetadataView
                waveformScrubberView
                    .padding(.top, DS.Spacing.xs)
                mainPlaybackControlsView
                    .padding(.top, DS.Spacing.sm)
                bottomDockCapsule
                    .padding(.top, DS.Spacing.xs)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, DS.Spacing.xxl)
        .frame(maxWidth: DS.Layout.maxSplitWidth)
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Cover Art
    
    private func coverArtView(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1.5)
                )
                .shadow(
                    color: Color.black.opacity(player.isPlaying ? 0.6 : 0.35),
                    radius: player.isPlaying ? 28 : 16,
                    x: 0,
                    y: player.isPlaying ? 14 : 8
                )
            
            if !book.coverImageName.isEmpty {
                CachedAsyncImage(
                    imageName: book.coverImageName,
                    placeholder: {
                        ProgressView()
                    },
                    fallback: {
                        coverFallbackView
                    }
                )
                .aspectRatio(1.0, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                coverFallbackView
            }
        }
        .scaleEffect(player.isPlaying ? 1.02 : 0.98)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: player.isPlaying)
    }
    
    private var coverFallbackView: some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: "headphones")
                .font(.system(size: 56, weight: .light))
                .foregroundColor(Color(red: 0.96, green: 0.46, blue: 0.18))
            
            Text(book.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, DS.Spacing.md)
        }
    }
    
    // MARK: - Title & Metadata
    
    private var titleAndMetadataView: some View {
        VStack(spacing: 5) {
            Text(book.title.uppercased())
                .font(.system(size: 20, weight: .bold, design: .default))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .tracking(0.5)
            
            Text(book.author)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(Color.white.opacity(0.85))
                .lineLimit(1)
            
            Text(currentChapterSubtitle)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(Color.white.opacity(0.55))
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
            
            VStack(spacing: 8) {
                // Waveform Bars with Timeline Animation
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !player.isPlaying)) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let phase = (time * 4.0).truncatingRemainder(dividingBy: .pi * 2)
                    
                    HStack(spacing: 3) {
                        ForEach(0..<barCount, id: \.self) { index in
                            let barProgress = Double(index) / Double(max(1, barCount - 1))
                            let isPlayed = barProgress <= progress
                            
                            // Live breathing animation around playhead when playing
                            let baseAmp = waveAmplitudes.indices.contains(index) ? waveAmplitudes[index] : 0.5
                            let liveMod = (player.isPlaying && isPlayed) ? (sin(phase + Double(index) * 0.55) * 0.15) : 0.0
                            let normalizedHeight = max(0.14, min(1.0, baseAmp + CGFloat(liveMod)))
                            let barHeight = normalizedHeight * 46.0
                            
                            RoundedRectangle(cornerRadius: 1.75, style: .continuous)
                                .fill(
                                    isPlayed
                                        ? AnyShapeStyle(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 1.0, green: 0.72, blue: 0.32),
                                                    Color(red: 0.96, green: 0.44, blue: 0.16)
                                                ],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        : AnyShapeStyle(Color.white.opacity(0.22))
                                )
                                .frame(maxWidth: .infinity)
                                .frame(height: barHeight)
                                .shadow(
                                    color: isPlayed ? Color(red: 0.96, green: 0.44, blue: 0.16).opacity(0.35) : .clear,
                                    radius: 2,
                                    x: 0,
                                    y: 0
                                )
                        }
                    }
                    .frame(height: 48, alignment: .center)
                }
                
                // Track line with Glowing Thumb
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 3)
                    
                    // Active filled track
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
                        .frame(width: max(0, totalWidth * CGFloat(progress)), height: 3)
                    
                    // Playhead Knob
                    Circle()
                        .fill(Color.white)
                        .frame(width: 9, height: 9)
                        .shadow(color: Color(red: 0.96, green: 0.44, blue: 0.16).opacity(0.8), radius: 4, x: 0, y: 0)
                        .offset(x: max(0, min(totalWidth - 9, totalWidth * CGFloat(progress) - 4.5)))
                }
                .frame(height: 12)
                
                // Timestamps (Elapsed & Remaining)
                HStack {
                    Text(AudiobookPlayerService.formatTimeDisplay(current, forceHours: hasHours))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.65))
                    
                    Spacer()
                    
                    let remaining = max(0.0, player.duration - current)
                    Text("-\(AudiobookPlayerService.formatTimeDisplay(remaining, forceHours: hasHours))")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
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
        .frame(height: 84)
    }
    
    // MARK: - Main Playback Controls
    
    private var mainPlaybackControlsView: some View {
        HStack(spacing: 36) {
            // Skip 15s Backward
            Button(action: {
                player.skipBackward(15)
                triggerHaptic()
            }) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                        .frame(width: 54, height: 54)
                    
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 22, weight: .medium))
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
                        .frame(width: 74, height: 74)
                        .shadow(
                            color: Color(red: 0.93, green: 0.38, blue: 0.12).opacity(0.48),
                            radius: 18,
                            x: 0,
                            y: 6
                        )
                    
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30, weight: .bold))
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
                        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                        .frame(width: 54, height: 54)
                    
                    Image(systemName: "goforward.15")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Skip forward 15 seconds")
        }
    }
    
    // MARK: - Bottom Dock Capsule
    
    private var bottomDockCapsule: some View {
        HStack(spacing: 16) {
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
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.96, green: 0.46, blue: 0.18).opacity(player.playbackRate != 1.0 ? 0.9 : 0.25))
                            .overlay(
                                Capsule().stroke(Color(red: 0.96, green: 0.46, blue: 0.18).opacity(0.65), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            
            // Chapters Drawer Button
            Button(action: {
                showChaptersSheet = true
                triggerHaptic()
            }) {
                VStack(spacing: 2) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Chapters")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(Color.white.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
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
                        .fill(player.sleepTimerRemaining != nil ? Color.white : Color.white.opacity(0.14))
                        .frame(width: 48, height: 32)
                    
                    Image(systemName: "moon.fill")
                        .font(.system(size: 14, weight: .semibold))
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
                .frame(width: 32, height: 32)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
