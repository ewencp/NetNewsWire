//
//  SpeechNowPlayingPresenter.swift
//  NetNewsWire-iOS
//

import UIKit
import MediaPlayer
import SpeechCoordinatorKit

/// Bridges `SpeechCoordinator` to the iOS lock-screen and Control Center
/// "Now Playing" UI. Owns:
/// - `MPNowPlayingInfoCenter` updates (driven by coordinator observer callbacks)
/// - `MPRemoteCommandCenter` registration and handlers (call back into coordinator)
/// - App-icon fallback artwork (cached at init)
///
/// Audio-session interruption recovery lives in `AudioBufferPlayer` (the
/// PCM player owned by `AppleSpeechSynth`), not here — the presenter
/// observes `SpeechCoordinator` state changes and reflects them in the
/// Now Playing UI without managing the underlying audio engine.
///
/// Held by `AppDelegate` as an app-lifetime singleton.
@MainActor
final class SpeechNowPlayingPresenter {

	private let coordinator: SpeechCoordinator
	private let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
	private let remoteCommandCenter = MPRemoteCommandCenter.shared()
	private let appIconArtwork: MPMediaItemArtwork?

	private var artworkFetchTask: URLSessionDataTask?
	private var lastSeenItemID: String?
	private var lastSeenArtwork: MPMediaItemArtwork?

	init(coordinator: SpeechCoordinator = .shared) {
		self.coordinator = coordinator
		self.appIconArtwork = Self.loadAppIconArtwork()

		coordinator.addObserver(self)
		registerRemoteCommandHandlers()
		nowPlayingInfoCenter.nowPlayingInfo = nil
	}

	// Note: no deinit cleanup. The presenter is an app-lifetime singleton, so
	// deinit only fires in tests. `URLSessionDataTask`s in flight either
	// complete or get cancelled when the network stack tears down. Adding
	// cleanup here would require accessing `@MainActor`-isolated state from
	// a nonisolated deinit, which Swift 6 rejects without an isolated-deinit
	// (which the broader project doesn't use).

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
			elapsedSeconds: coordinator.elapsedSeconds,
			totalDurationSeconds: coordinator.durationSeconds
		)
		if let artwork = lastSeenArtwork {
			dict[MPMediaItemPropertyArtwork] = artwork
		}
		nowPlayingInfoCenter.nowPlayingInfo = dict
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

		remoteCommandCenter.changePlaybackPositionCommand.isEnabled = true
		remoteCommandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
			MainActor.assumeIsolated { () -> MPRemoteCommandHandlerStatus in
				guard let self,
				      let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
					return .commandFailed
				}
				self.coordinator.seek(toSeconds: positionEvent.positionTime)
				return .success
			}
		}

		// Defensively disable commands we do not handle. MPRemoteCommandCenter
		// is a singleton with persistent state; prior process registrations
		// can leak across launches in some scenarios.
		remoteCommandCenter.nextTrackCommand.isEnabled = false
		remoteCommandCenter.previousTrackCommand.isEnabled = false
		remoteCommandCenter.stopCommand.isEnabled = false
	}
}

// MARK: - SpeechCoordinatorObserver

extension SpeechNowPlayingPresenter: SpeechCoordinatorObserver {
	func speechCoordinatorDidUpdate(_ coordinator: SpeechCoordinator) {
		handleCoordinatorUpdate()
	}
}
