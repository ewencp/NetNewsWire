//
//  SpeechNowPlayingPresenter.swift
//  NetNewsWire-iOS
//

import UIKit
import MediaPlayer
import AVFoundation
import SpeechCoordinatorKit

/// Bridges `SpeechCoordinator` to the iOS lock-screen and Control Center
/// "Now Playing" UI. Owns:
/// - `MPNowPlayingInfoCenter` updates (driven by coordinator observer callbacks)
/// - `MPRemoteCommandCenter` registration and handlers (call back into coordinator)
/// - `AVAudioSession.interruptionNotification` observation
/// - App-icon fallback artwork (cached at init)
///
/// Held by `AppDelegate` as an app-lifetime singleton.
@MainActor
final class SpeechNowPlayingPresenter {

	private let coordinator: SpeechCoordinator
	private let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
	private let remoteCommandCenter = MPRemoteCommandCenter.shared()
	private let appIconArtwork: MPMediaItemArtwork?

	/// Single bit of presenter state for the interruption state machine.
	private var pendingResumeFromInterruption: Bool = false

	private var artworkFetchTask: URLSessionDataTask?
	private var lastSeenItemID: String?
	private var lastSeenArtwork: MPMediaItemArtwork?
	private var interruptionObservationToken: NSObjectProtocol?

	/// Approximate words-per-minute baseline. The default speech rate
	/// (`SpeechDefaults.defaultRateMultiplier`, multiplier 1.0) maps to roughly
	/// 180 wpm with the typical voice. The coordinator's current rate
	/// multiplier scales this linearly for the duration estimate.
	private let baseWordsPerMinute: Double = 180

	init(coordinator: SpeechCoordinator = .shared) {
		self.coordinator = coordinator
		self.appIconArtwork = Self.loadAppIconArtwork()

		coordinator.addObserver(self)
		registerRemoteCommandHandlers()
		observeInterruptionNotifications()
		nowPlayingInfoCenter.nowPlayingInfo = nil
	}

	// Note: no deinit cleanup. The presenter is an app-lifetime singleton, so
	// deinit only fires in tests. The interruption observer's closure captures
	// `self` weakly and becomes a no-op once the presenter deallocates;
	// `URLSessionDataTask`s in flight either complete or get cancelled when
	// the network stack tears down. Adding cleanup here would require accessing
	// `@MainActor`-isolated state from a nonisolated deinit, which Swift 6
	// rejects without an isolated-deinit (which the broader project doesn't use).

	// MARK: - Artwork loading

	private static func loadAppIconArtwork() -> MPMediaItemArtwork? {
		guard let image = UIImage(named: "AppIcon") else {
			return nil
		}
		return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
	}

	private func kickOffArtworkFetch(url: URL, forArticleID articleID: String) {
		let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
			guard let data, let image = UIImage(data: data) else { return }
			let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
			Task { @MainActor in
				guard let self else { return }
				// Stale-fetch guard: if the playing item changed during the fetch,
				// discard this result.
				guard self.coordinator.playingItem?.articleID == articleID else { return }
				self.lastSeenArtwork = artwork
				self.updateNowPlayingInfo()
			}
		}
		artworkFetchTask = task
		task.resume()
	}

	// MARK: - Coordinator observer

	private func handleCoordinatorUpdate() {
		// Safety: if the user resumed manually mid-interruption, clear the
		// pending-resume flag so the system's later resume hint doesn't
		// double-toggle.
		if pendingResumeFromInterruption,
		   case .speaking = coordinator.state {
			pendingResumeFromInterruption = false
		}

		guard let item = coordinator.playingItem else {
			// Idle / finished — clear the now-playing UI and tear down artwork fetch.
			artworkFetchTask?.cancel()
			artworkFetchTask = nil
			lastSeenItemID = nil
			lastSeenArtwork = nil
			nowPlayingInfoCenter.nowPlayingInfo = nil
			return
		}

		let isNewItem = lastSeenItemID != item.articleID

		if isNewItem {
			lastSeenItemID = item.articleID
			artworkFetchTask?.cancel()
			artworkFetchTask = nil
			lastSeenArtwork = appIconArtwork
			if let url = item.imageURL {
				kickOffArtworkFetch(url: url, forArticleID: item.articleID)
			}
		}

		// Skip nowPlayingInfo writes during the transient `.preparing` state
		// for an existing item (e.g., during a within-article skip). The
		// builder maps `.preparing` to elapsed=0, which iOS reads as
		// "playback restarted from zero" and visually flashes the lock-screen
		// progress bar back to 0 before animating to the new position. The
		// follow-up `.speaking(newBlockIndex)` fires within a fraction of a
		// second and refreshes with the correct elapsed time, so the brief
		// skip is invisible to the user. New items still update during
		// `.preparing` so the lock-screen swaps to the new article promptly
		// rather than showing the previous item's info during the gap.
		if case .preparing = coordinator.state, !isNewItem {
			return
		}

		updateNowPlayingInfo()
	}

	private func updateNowPlayingInfo() {
		guard let item = coordinator.playingItem else {
			nowPlayingInfoCenter.nowPlayingInfo = nil
			return
		}
		var dict = NowPlayingInfoBuilder.buildInfo(
			metadata: item,
			state: coordinator.state,
			wordsPerMinute: currentEffectiveWordsPerMinute()
		)
		if let artwork = lastSeenArtwork {
			dict[MPMediaItemPropertyArtwork] = artwork
		}
		nowPlayingInfoCenter.nowPlayingInfo = dict
	}

	private func currentEffectiveWordsPerMinute() -> Double {
		let multiplier = max(Double(coordinator.currentRateMultiplier), 0.05)
		return baseWordsPerMinute * multiplier
	}

	// MARK: - Remote command center

	private func registerRemoteCommandHandlers() {
		remoteCommandCenter.togglePlayPauseCommand.isEnabled = true
		remoteCommandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
			MainActor.assumeIsolated { () -> MPRemoteCommandHandlerStatus in
				guard let self else { return .commandFailed }
				self.coordinator.togglePlayPause()
				return .success
			}
		}

		remoteCommandCenter.playCommand.isEnabled = true
		remoteCommandCenter.playCommand.addTarget { [weak self] _ in
			MainActor.assumeIsolated { () -> MPRemoteCommandHandlerStatus in
				guard let self else { return .commandFailed }
				if case .paused = self.coordinator.state {
					self.coordinator.togglePlayPause()
					return .success
				}
				return .noActionableNowPlayingItem
			}
		}

		remoteCommandCenter.pauseCommand.isEnabled = true
		remoteCommandCenter.pauseCommand.addTarget { [weak self] _ in
			MainActor.assumeIsolated { () -> MPRemoteCommandHandlerStatus in
				guard let self else { return .commandFailed }
				if case .speaking = self.coordinator.state {
					self.coordinator.togglePlayPause()
					return .success
				}
				return .noActionableNowPlayingItem
			}
		}

		remoteCommandCenter.skipForwardCommand.isEnabled = true
		remoteCommandCenter.skipForwardCommand.preferredIntervals = [30]
		remoteCommandCenter.skipForwardCommand.addTarget { [weak self] _ in
			MainActor.assumeIsolated { () -> MPRemoteCommandHandlerStatus in
				guard let self else { return .commandFailed }
				self.coordinator.skipForward()
				return .success
			}
		}

		remoteCommandCenter.skipBackwardCommand.isEnabled = true
		remoteCommandCenter.skipBackwardCommand.preferredIntervals = [30]
		remoteCommandCenter.skipBackwardCommand.addTarget { [weak self] _ in
			MainActor.assumeIsolated { () -> MPRemoteCommandHandlerStatus in
				guard let self else { return .commandFailed }
				self.coordinator.skipBackward()
				return .success
			}
		}

		// Defensively disable commands we do not handle. MPRemoteCommandCenter
		// is a singleton with persistent state; prior process registrations
		// can leak across launches in some scenarios.
		remoteCommandCenter.nextTrackCommand.isEnabled = false
		remoteCommandCenter.previousTrackCommand.isEnabled = false
		remoteCommandCenter.changePlaybackPositionCommand.isEnabled = false
		remoteCommandCenter.stopCommand.isEnabled = false
	}

	// MARK: - Audio session interruption

	private func observeInterruptionNotifications() {
		interruptionObservationToken = NotificationCenter.default.addObserver(
			forName: AVAudioSession.interruptionNotification,
			object: nil,
			queue: nil
		) { [weak self] notification in
			// AVAudioSession posts on a background queue. Extract Sendable
			// primitives from the notification on whatever queue we're on
			// (Notification itself isn't Sendable), then hop to main with
			// just those values.
			guard let info = notification.userInfo,
			      let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt else {
				return
			}
			let optionsRaw = (info[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
			Task { @MainActor in
				self?.handleInterruption(typeValue: typeValue, optionsRaw: optionsRaw)
			}
		}
	}

	private func handleInterruption(typeValue: UInt, optionsRaw: UInt) {
		guard let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
			return
		}

		let event: InterruptionEvent
		switch type {
		case .began:
			event = .began
		case .ended:
			let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
			event = .ended(shouldResume: options.contains(.shouldResume))
		@unknown default:
			return
		}

		let outcome = InterruptionStateMachine.transition(
			currentState: coordinator.state,
			event: event,
			pendingResume: pendingResumeFromInterruption
		)
		pendingResumeFromInterruption = outcome.newPendingResume
		switch outcome.action {
		case .togglePlayPause:
			coordinator.togglePlayPause()
		case .none:
			break
		}
	}
}

// MARK: - SpeechCoordinatorObserver

extension SpeechNowPlayingPresenter: SpeechCoordinatorObserver {
	func speechCoordinatorDidUpdate(_ coordinator: SpeechCoordinator) {
		handleCoordinatorUpdate()
	}
}
