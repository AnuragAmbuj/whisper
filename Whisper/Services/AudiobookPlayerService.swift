//
//  AudiobookPlayerService.swift
//  Whisper
//
//  Created by Anurag Ambuj on 28/09/26.
//

import Foundation
import AVFoundation
import SwiftUI
import Combine

#if canImport(MediaPlayer)
import MediaPlayer
#endif

@Observable
final class AudiobookPlayerService {
    static let shared = AudiobookPlayerService()
    
    // Playback state
    var isPlaying: Bool = false
    var currentTime: Double = 0.0
    var duration: Double = 1.0
    var playbackRate: Float = 1.0
    var currentChapterIndex: Int = 0
    var chapters: [AudiobookChapter] = []
    
    // Sleep timer state
    var sleepTimerRemaining: TimeInterval? = nil
    
    // Internal player
    private var avPlayer: AVPlayer?
    private var timeObserverToken: Any?
    private var timerSubscription: AnyCancellable?
    private var sleepTimerTask: Task<Void, Never>?
    
    private(set) weak var currentBook: Book?
    private var onProgressUpdate: ((Double, Int) -> Void)?
    
    struct AudiobookChapter: Identifiable, Hashable {
        let id = UUID()
        let title: String
        let startTime: Double
        let duration: Double
        
        var formattedStartTime: String {
            AudiobookPlayerService.formatTime(startTime)
        }
    }
    
    init() {
        configureAudioSession()
        setupRemoteCommands()
    }
    
    deinit {
        cleanup()
    }
    
    private func configureAudioSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AudiobookPlayerService: Audio session configuration failed: \(error)")
        }
        #endif
    }
    
    func loadBook(
        _ book: Book,
        onProgressUpdate: ((Double, Int) -> Void)? = nil
    ) {
        if currentBook?.id == book.id && (avPlayer != nil || timerSubscription != nil) {
            // Already loaded this book, keep state
            self.onProgressUpdate = onProgressUpdate
            return
        }
        
        cleanup()
        self.currentBook = book
        self.onProgressUpdate = onProgressUpdate
        
        // Setup chapters: parse or synthesize based on duration
        setupChapters(for: book)
        
        // Initialize position from saved book progress
        let initialTime = book.progress * duration
        self.currentTime = max(0.0, min(initialTime, duration))
        
        // Check if real audio file exists
        if let audioURL = book.resolvedURL, FileManager.default.fileExists(atPath: audioURL.path) {
            setupRealAudioPlayer(url: audioURL)
        } else {
            // Mock preview audio mode
            setupMockAudioPlayer()
        }
        
        updateNowPlaying()
    }
    
    private func setupRealAudioPlayer(url: URL) {
        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        self.avPlayer = player
        
        Task { [weak self] in
            guard let self = self else { return }
            if let durationTime = try? await asset.load(.duration) {
                let seconds = CMTimeGetSeconds(durationTime)
                if seconds.isFinite && seconds > 0 {
                    await MainActor.run {
                        self.duration = seconds
                        self.setupChapters(for: self.currentBook)
                    }
                }
            }
        }
        
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        self.timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let currentSec = CMTimeGetSeconds(time)
            if currentSec.isFinite && !currentSec.isNaN {
                self.currentTime = currentSec
                self.updateChapterIndex()
                self.syncProgress()
            }
        }
        
        // Seek to initial time
        let targetCMTime = CMTime(seconds: currentTime, preferredTimescale: 600)
        player.seek(to: targetCMTime)
    }
    
    private func setupMockAudioPlayer() {
        // Fallback for sample books without local audio binary
        if duration <= 1.0 {
            self.duration = 1800.0 // Default 30 min duration for sample
        }
        
        // Timer-based playback tick
        timerSubscription = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, self.isPlaying else { return }
                let newTime = self.currentTime + (0.5 * Double(self.playbackRate))
                if newTime >= self.duration {
                    self.currentTime = self.duration
                    self.pause()
                } else {
                    self.currentTime = newTime
                }
                self.updateChapterIndex()
                self.syncProgress()
            }
    }
    
    private func setupChapters(for book: Book?) {
        guard let book = book else { return }
        
        // If content contains chapters or cues, extract them
        if duration <= 1.0 {
            duration = 3600.0 * 2.5 // ~2.5 hours default
        }
        
        let total = duration
        let chapterCount = 6
        let chapterDuration = total / Double(chapterCount)
        
        self.chapters = (0..<chapterCount).map { index in
            AudiobookChapter(
                title: "Chapter \(index + 1)",
                startTime: Double(index) * chapterDuration,
                duration: chapterDuration
            )
        }
    }
    
    // MARK: - Playback Controls
    
    func play() {
        guard !isPlaying else { return }
        isPlaying = true
        
        if let player = avPlayer {
            player.rate = playbackRate
            player.play()
        }
        updateNowPlaying()
    }
    
    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        
        if let player = avPlayer {
            player.pause()
        }
        updateNowPlaying()
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func seek(to time: Double) {
        let clamped = max(0.0, min(time, duration))
        self.currentTime = clamped
        
        if let player = avPlayer {
            let cmTime = CMTime(seconds: clamped, preferredTimescale: 600)
            player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        
        updateChapterIndex()
        syncProgress()
        updateNowPlaying()
    }
    
    func skipForward(_ seconds: Double = 30.0) {
        seek(to: currentTime + seconds)
    }
    
    func skipBackward(_ seconds: Double = 15.0) {
        seek(to: currentTime - seconds)
    }
    
    func setPlaybackRate(_ rate: Float) {
        self.playbackRate = rate
        if isPlaying, let player = avPlayer {
            player.rate = rate
        }
        updateNowPlaying()
    }
    
    func jumpToChapter(_ chapter: AudiobookChapter) {
        seek(to: chapter.startTime)
    }
    
    // MARK: - Sleep Timer
    
    func setSleepTimer(minutes: Int?) {
        sleepTimerTask?.cancel()
        guard let minutes = minutes, minutes > 0 else {
            sleepTimerRemaining = nil
            return
        }
        
        let seconds = TimeInterval(minutes * 60)
        self.sleepTimerRemaining = seconds
        
        sleepTimerTask = Task { [weak self] in
            var remaining = seconds
            while remaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                remaining -= 1
                await MainActor.run {
                    self?.sleepTimerRemaining = remaining
                }
            }
            await MainActor.run {
                self?.sleepTimerRemaining = nil
                self?.pause()
            }
        }
    }
    
    // MARK: - Progress Synchronization
    
    private func syncProgress() {
        guard duration > 0 else { return }
        let progress = currentTime / duration
        let location = Int(currentTime)
        onProgressUpdate?(progress, location)
    }
    
    private func updateChapterIndex() {
        for (index, ch) in chapters.enumerated().reversed() {
            if currentTime >= ch.startTime {
                self.currentChapterIndex = index
                return
            }
        }
        self.currentChapterIndex = 0
    }
    

    // MARK: - Remote Command Center (Lock Screen & Control Center)
    
    private func setupRemoteCommands() {
        #if canImport(MediaPlayer)
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.play()
            return .success
        }
        
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.pause()
            return .success
        }
        
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.togglePlayPause()
            return .success
        }
        
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.skipForward(15)
            return .success
        }
        
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.skipBackward(15)
            return .success
        }
        
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.seek(to: positionEvent.positionTime)
            return .success
        }
        #endif
    }

    // MARK: - Now Playing Info Center
    
    private func updateNowPlaying() {
        #if canImport(MediaPlayer)
        guard let book = currentBook else { return }
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = book.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = book.author
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackRate) : 0.0
        
        #if os(iOS)
        if !book.coverImageName.isEmpty,
           let uiImage = UIImage(named: book.coverImageName) ?? UIImage(contentsOfFile: book.coverImageName) {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: uiImage.size) { _ in uiImage }
        }
        #endif
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        #endif
    }
    
    func cleanup() {
        pause()
        if let token = timeObserverToken, let player = avPlayer {
            player.removeTimeObserver(token)
            self.timeObserverToken = nil
        }
        self.avPlayer = nil
        self.timerSubscription?.cancel()
        self.timerSubscription = nil
        self.sleepTimerTask?.cancel()
        self.sleepTimerTask = nil
    }
    
    static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && !seconds.isNaN && seconds >= 0 else { return "0:00" }
        let totalSecs = Int(seconds)
        let hours = totalSecs / 3600
        let minutes = (totalSecs % 3600) / 60
        let secs = totalSecs % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    static func formatTimeDisplay(_ seconds: Double, forceHours: Bool = false) -> String {
        guard seconds.isFinite && !seconds.isNaN && seconds >= 0 else { return "00:00" }
        let totalSecs = Int(seconds)
        let hours = totalSecs / 3600
        let minutes = (totalSecs % 3600) / 60
        let secs = totalSecs % 60
        
        if hours > 0 || forceHours {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
}
