//
//  AudiobookPlayerView.swift
//  Whisper
//
//  Created by Anurag Ambuj on 28/09/26.
//

import SwiftUI

struct AudiobookPlayerView: View {
    let book: Book
    @Bindable var viewModel: ReaderViewModel
    @Binding var showControls: Bool
    
    @State private var player = AudiobookPlayerService.shared
    @State private var isScrubbing: Bool = false
    @State private var scrubTime: Double = 0.0
    @State private var showChaptersSheet: Bool = false
    @State private var showSpeedMenu: Bool = false
    @State private var showSleepTimerSheet: Bool = false
    @State private var pulseWave: Bool = false
    
    private let playbackRates: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    private let sleepTimerOptions: [Int] = [5, 15, 30, 45, 60]
    
    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            
            ZStack {
                // Background Ambient Glow
                ambientBackground
                
                if isLandscape {
                    landscapeLayout
                        .padding(.horizontal, DS.Spacing.xxl)
                } else {
                    portraitLayout
                        .padding(.horizontal, DS.Spacing.xl)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                setupPlayer()
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
    
    private func setupPlayer() {
        player.loadBook(book) { progress, location in
            viewModel.updateProgress(progress)
            viewModel.updateLocation(location)
        }
    }
    
    // MARK: - Ambient Background
    
    private var ambientBackground: some View {
        ZStack {
            viewModel.theme.backgroundColor
                .ignoresSafeArea()
            
            // Subtle liquid glow orb
            Circle()
                .fill(DS.Colors.accent.opacity(player.isPlaying ? 0.15 : 0.06))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(y: -40)
                .animation(.easeInOut(duration: 1.5), value: player.isPlaying)
        }
    }
    
    // MARK: - Portrait Layout
    
    private var portraitLayout: some View {
        VStack(spacing: DS.Spacing.lg) {
            Spacer(minLength: 40)
            
            // Cover Art with Dynamic Elevation
            coverArtView
                .frame(maxWidth: 260, maxHeight: 260)
                .padding(.top, DS.Spacing.md)
            
            // Title & Author & Chapter Meta
            titleAndMetadataView
                .padding(.top, DS.Spacing.sm)
            
            // Animated Sound Wave
            soundWaveformView
                .frame(height: 28)
                .padding(.vertical, DS.Spacing.xs)
            
            // Scrubber Bar & Times
            scrubberSection
                .padding(.horizontal, DS.Spacing.xs)
            
            // Main Controls (Speed, Skip, Play/Pause, Skip, Chapters)
            playbackControlsView
                .padding(.top, DS.Spacing.sm)
            
            // Auxiliary Controls (Sleep timer, Bookmarks)
            auxiliaryControlsView
                .padding(.top, DS.Spacing.xs)
            
            Spacer(minLength: 30)
        }
        .frame(maxWidth: DS.Layout.maxContentWidth)
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Landscape Layout
    
    private var landscapeLayout: some View {
        HStack(spacing: DS.Spacing.xxl) {
            // Left: Cover Art
            VStack {
                coverArtView
                    .frame(maxWidth: 240, maxHeight: 240)
                
                soundWaveformView
                    .frame(height: 24)
                    .padding(.top, DS.Spacing.md)
            }
            .frame(maxWidth: .infinity)
            
            // Right: Player Controls
            VStack(spacing: DS.Spacing.md) {
                titleAndMetadataView
                
                scrubberSection
                    .padding(.top, DS.Spacing.sm)
                
                playbackControlsView
                    .padding(.top, DS.Spacing.sm)
                
                auxiliaryControlsView
                    .padding(.top, DS.Spacing.xs)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: DS.Layout.maxSplitWidth)
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Cover Art
    
    private var coverArtView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(DS.Colors.cardBackground)
                .aspectRatio(1.0, contentMode: .fit)
                .shadow(
                    color: Color.black.opacity(player.isPlaying ? 0.25 : 0.12),
                    radius: player.isPlaying ? 24 : 12,
                    x: 0,
                    y: player.isPlaying ? 12 : 6
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                        .stroke(DS.Colors.border, lineWidth: 1)
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
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            } else {
                coverFallbackView
            }
        }
        .scaleEffect(player.isPlaying ? 1.02 : 0.98)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: player.isPlaying)
    }
    
    private var coverFallbackView: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "headphones")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(DS.Colors.accent)
            
            Text(book.title)
                .font(.headline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, DS.Spacing.md)
        }
    }
    
    // MARK: - Title & Metadata
    
    private var titleAndMetadataView: some View {
        VStack(spacing: 4) {
            Button(action: { showChaptersSheet = true }) {
                HStack(spacing: 4) {
                    Text(currentChapterTitle)
                        .font(.caption.bold())
                        .foregroundColor(DS.Colors.accent)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(DS.Colors.accent)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(DS.Colors.cardBackground)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(DS.Colors.border, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            
            Text(book.title)
                .font(.title2.bold())
                .foregroundColor(viewModel.theme.textColor)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            
            Text(book.author)
                .font(.subheadline)
                .foregroundColor(viewModel.theme.textColor.opacity(0.7))
                .lineLimit(1)
        }
    }
    
    private var currentChapterTitle: String {
        if player.chapters.indices.contains(player.currentChapterIndex) {
            return player.chapters[player.currentChapterIndex].title
        }
        return "Audiobook"
    }
    
    // MARK: - Animated Waveform Indicator
    
    private var soundWaveformView: some View {
        HStack(spacing: 4) {
            ForEach(0..<18) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(DS.Colors.accent.opacity(player.isPlaying ? 0.8 : 0.25))
                    .frame(
                        width: 3,
                        height: player.isPlaying
                            ? CGFloat(max(6, (sin(Double(index) * 0.7 + (pulseWave ? 2.5 : 0)) + 1.2) * 10))
                            : 6
                    )
                    .animation(
                        player.isPlaying
                            ? Animation.easeInOut(duration: 0.45).repeatForever().delay(Double(index) * 0.04)
                            : .default,
                        value: pulseWave
                    )
            }
        }
        .onAppear {
            pulseWave = true
        }
    }
    
    // MARK: - Scrubber Section
    
    private var scrubberSection: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubTime : player.currentTime },
                    set: { newValue in
                        scrubTime = newValue
                        if !isScrubbing {
                            isScrubbing = true
                        }
                    }
                ),
                in: 0...max(1.0, player.duration)
            ) { editing in
                if !editing && isScrubbing {
                    player.seek(to: scrubTime)
                    viewModel.flushReadingProgressToCloud()
                    isScrubbing = false
                }
            }
            .tint(DS.Colors.accent)
            
            HStack {
                let displayCurrent = isScrubbing ? scrubTime : player.currentTime
                Text(AudiobookPlayerService.formatTime(displayCurrent))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(viewModel.theme.textColor.opacity(0.6))
                
                Spacer()
                
                let remaining = max(0.0, player.duration - displayCurrent)
                Text("-\(AudiobookPlayerService.formatTime(remaining))")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(viewModel.theme.textColor.opacity(0.6))
            }
        }
    }
    
    // MARK: - Playback Controls
    
    private var playbackControlsView: some View {
        HStack(spacing: DS.Spacing.xl) {
            // Speed button
            Menu {
                ForEach(playbackRates, id: \.self) { rate in
                    Button(action: { player.setPlaybackRate(rate) }) {
                        HStack {
                            Text(String(format: "%.2fx", rate))
                            if player.playbackRate == rate {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(String(format: "%.2fx", player.playbackRate))
                    .font(.caption.bold())
                    .foregroundColor(viewModel.theme.textColor)
                    .frame(width: 46, height: 32)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(viewModel.theme.textColor.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            
            // Skip Back 15s
            Button(action: { player.skipBackward(15) }) {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(viewModel.theme.textColor)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Skip backward 15 seconds")
            
            // Play / Pause Primary Glass Button
            Button(action: {
                player.togglePlayPause()
                viewModel.flushReadingProgressToCloud()
            }) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(DS.Colors.onSelection)
                    .frame(width: 68, height: 68)
                    .background(Color.primary)
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            
            // Skip Forward 30s
            Button(action: { player.skipForward(30) }) {
                Image(systemName: "goforward.30")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(viewModel.theme.textColor)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Skip forward 30 seconds")
            
            // Chapters Drawer Button
            Button(action: { showChaptersSheet = true }) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(viewModel.theme.textColor)
                    .frame(width: 46, height: 32)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(viewModel.theme.textColor.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View Chapters")
        }
    }
    
    // MARK: - Auxiliary Controls (Sleep Timer & Bookmark)
    
    private var auxiliaryControlsView: some View {
        HStack(spacing: DS.Spacing.xxl) {
            // Sleep Timer Button
            Button(action: { showSleepTimerSheet = true }) {
                HStack(spacing: 4) {
                    Image(systemName: player.sleepTimerRemaining != nil ? "moon.zzz.fill" : "moon.zzz")
                    if let remaining = player.sleepTimerRemaining {
                        Text(AudiobookPlayerService.formatTime(remaining))
                            .font(.caption2.bold().monospacedDigit())
                    } else {
                        Text("Sleep")
                            .font(.caption)
                    }
                }
                .foregroundColor(player.sleepTimerRemaining != nil ? DS.Colors.accent : viewModel.theme.textColor.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            
            // Bookmark Timestamp
            Button(action: {
                viewModel.toggleBookmark()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.isBookmarked ? "bookmark.fill" : "bookmark")
                    Text("Bookmark")
                        .font(.caption)
                }
                .foregroundColor(viewModel.isBookmarked ? DS.Colors.accent : viewModel.theme.textColor.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Chapters Sheet
    
    private var chaptersSheet: some View {
        NavigationStack {
            List {
                ForEach(player.chapters) { chapter in
                    Button(action: {
                        player.jumpToChapter(chapter)
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
                                    .foregroundColor(DS.Colors.accent)
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
                    showSleepTimerSheet = false
                }) {
                    HStack {
                        Text("Off")
                        Spacer()
                        if player.sleepTimerRemaining == nil {
                            Image(systemName: "checkmark")
                                .foregroundColor(DS.Colors.accent)
                        }
                    }
                }
                
                ForEach(sleepTimerOptions, id: \.self) { mins in
                    Button(action: {
                        player.setSleepTimer(minutes: mins)
                        showSleepTimerSheet = false
                    }) {
                        HStack {
                            Text("\(mins) minutes")
                            Spacer()
                            if let remaining = player.sleepTimerRemaining, Int(remaining / 60) == mins {
                                Image(systemName: "checkmark")
                                    .foregroundColor(DS.Colors.accent)
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
