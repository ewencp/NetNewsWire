//
//  SpeechCoordinator.swift
//  NetNewsWire
//

import Foundation
import Articles
import ArticleSpeech
import AppleSpeechKit

@MainActor
public final class SpeechCoordinator {

	public static let shared = SpeechCoordinator()

	public private(set) var state: SpeechSynthState = .idle
	public private(set) var playingArticleID: String? = nil
	public private(set) var playingArticleTitle: String? = nil

	private let synth: SpeechSynth
	private let observers = NSHashTable<AnyObject>.weakObjects()

	/// Set when a content swap (e.g., summarize while paused) wants to preserve
	/// the paused state across the new playback. Cleared after the synth's first
	/// `.speaking` transition triggers a re-pause.
	private var pauseAfterStart: Bool = false

	/// Cached blocks for the currently-playing article so that voice/rate
	/// changes from Settings can re-trigger playback without re-running the
	/// full HTML preprocessing pipeline.
	private var cachedBlocks: [SpeechBlock] = []
	private var cachedArticle: Article?

	private init() {
		self.synth = AppleSpeechSynth()
		self.synth.addObserver(self)
	}

	/// Test/internal initializer that allows substituting a different synth.
	internal init(synth: SpeechSynth) {
		self.synth = synth
		self.synth.addObserver(self)
	}

	// MARK: - Public API

	/// Start playback for the given article and source HTML.
	///
	/// - Parameter keepPaused: When true, the synth will be re-paused immediately
	///   after the first block starts speaking. Used by content-swap flows
	///   (Reader View / Summarize toggles on the playing article) to preserve
	///   the user's paused state across the swap.
	public func startPlayback(for article: Article, sourceHTML: String, keepPaused: Bool = false) {
		let articleID = article.articleID
		let title = article.title

		Task { @MainActor in
			let content = SpeechPreprocessor.preprocess(
				html: sourceHTML,
				articleID: articleID,
				title: title,
				language: Locale.current.language.languageCode?.identifier
			)
			let blocks = await SpeechBlockBuilder.makeBlocks(from: content)

			let voice = currentVoice(for: article)
			let rate = currentRate(for: article)

			playingArticleID = articleID
			playingArticleTitle = title
			pauseAfterStart = keepPaused
			cachedBlocks = blocks
			cachedArticle = article
			notifyObservers()
			synth.play(blocks: blocks, voice: voice, rate: rate, startingAt: 0)
		}
	}

	/// Restart the active playback with the latest voice/rate from `UserDefaults`,
	/// resuming at the current block. No-op if nothing is playing. Preserves the
	/// paused state across the swap.
	public func applyCurrentSettings() {
		guard state.isActive, let article = cachedArticle, !cachedBlocks.isEmpty else {
			return
		}
		let voice = currentVoice(for: article)
		let rate = currentRate(for: article)
		let resumeIndex: Int
		switch state {
		case .speaking(let i, _), .paused(let i, _): resumeIndex = i
		default:                                      resumeIndex = 0
		}
		let wasPaused: Bool
		if case .paused = state { wasPaused = true } else { wasPaused = false }
		pauseAfterStart = wasPaused
		synth.play(blocks: cachedBlocks, voice: voice, rate: rate, startingAt: resumeIndex)
	}

	public func togglePlayPause() {
		switch state {
		case .speaking:
			synth.pause()
		case .paused:
			synth.resume()
		default:
			break
		}
	}

	public func stop() { synth.stop() }
	public func skipForward() { synth.skipForward() }
	public func skipBackward() { synth.skipBackward() }

	public func setRate(_ rateMultiplier: Float) {
		UserDefaults.standard.set(rateMultiplier, forKey: SpeechDefaults.rateMultiplierKey)
	}

	public func setVoice(_ voice: SpeechVoice) {
		UserDefaults.standard.set(voice.identifier, forKey: SpeechDefaults.voiceIdentifierKey)
	}

	public func addObserver(_ observer: SpeechCoordinatorObserver) {
		observers.add(observer)
	}

	public func removeObserver(_ observer: SpeechCoordinatorObserver) {
		observers.remove(observer)
	}

	// MARK: - Private

	private func currentVoice(for article: Article) -> SpeechVoice {
		// Future: per-feed override hook reads article.feedID for a per-feed setting.
		if let identifier = UserDefaults.standard.string(forKey: SpeechDefaults.voiceIdentifierKey) {
			let installed = AppleSpeechVoiceCatalog.installedVoices(matching: "")
			if let match = installed.first(where: { $0.identifier == identifier }) {
				return match
			}
		}
		return AppleSpeechVoiceCatalog.systemDefault
	}

	private func currentRate(for article: Article) -> Float {
		// Future: per-feed override.
		let stored = UserDefaults.standard.float(forKey: SpeechDefaults.rateMultiplierKey)
		return stored == 0 ? SpeechDefaults.defaultRateMultiplier : stored
	}

	private func notifyObservers() {
		for case let observer as SpeechCoordinatorObserver in observers.allObjects {
			observer.speechCoordinatorDidUpdate(self)
		}
	}
}

// MARK: - SpeechSynthObserver

extension SpeechCoordinator: SpeechSynthObserver {

	public func speechSynth(_ synth: SpeechSynth, didChangeState newState: SpeechSynthState) {
		state = newState
		switch newState {
		case .finished, .idle:
			playingArticleID = nil
			playingArticleTitle = nil
			pauseAfterStart = false
			cachedBlocks = []
			cachedArticle = nil
		case .speaking:
			if pauseAfterStart {
				pauseAfterStart = false
				synth.pause()
			}
		default:
			break
		}
		notifyObservers()
	}
}
