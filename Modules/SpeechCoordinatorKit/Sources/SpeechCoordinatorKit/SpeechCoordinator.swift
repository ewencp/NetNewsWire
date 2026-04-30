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

	public func startPlayback(for article: Article, sourceHTML: String) {
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
			notifyObservers()
			synth.play(blocks: blocks, voice: voice, rate: rate)
		}
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
		default:
			break
		}
		notifyObservers()
	}
}
