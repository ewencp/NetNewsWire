//
//  MockSpeechSynth.swift
//  SpeechCoordinatorKitTests
//

import Foundation
import ArticleSpeech

@MainActor
final class MockSpeechSynth: SpeechSynth {

	var state: SpeechSynthState = .idle
	var isAvailable: Bool { get async { true } }

	var durationSeconds: Double = 0
	var elapsedSeconds: Double = 0

	private(set) var playCount = 0
	private(set) var pauseCount = 0
	private(set) var resumeCount = 0
	private(set) var stopCount = 0
	private(set) var skipForwardCount = 0
	private(set) var skipBackwardCount = 0
	private(set) var seekCount = 0
	private(set) var lastBlocks: [SpeechBlock] = []
	private(set) var lastVoice: SpeechVoice?
	private(set) var lastRate: Float?
	private(set) var lastStartingAt: Int?
	private(set) var lastSeekSeconds: Double?

	private let observers = NSHashTable<AnyObject>.weakObjects()

	func availableVoices() async -> [SpeechVoice] { [] }

	func play(blocks: [SpeechBlock], voice: SpeechVoice, rate: Float, startingAt: Int) {
		playCount += 1
		lastBlocks = blocks
		lastVoice = voice
		lastRate = rate
		lastStartingAt = startingAt
	}

	func pause() { pauseCount += 1 }
	func resume() { resumeCount += 1 }
	func stop() { stopCount += 1 }
	func skipForward() { skipForwardCount += 1 }
	func skipBackward() { skipBackwardCount += 1 }

	func seek(toSeconds seconds: Double) {
		seekCount += 1
		lastSeekSeconds = seconds
	}

	func addObserver(_ observer: SpeechSynthObserver) { observers.add(observer) }
	func removeObserver(_ observer: SpeechSynthObserver) { observers.remove(observer) }

	/// Test helper: simulate a state change.
	func simulateStateChange(_ newState: SpeechSynthState) {
		state = newState
		for case let observer as SpeechSynthObserver in observers.allObjects {
			observer.speechSynth(self, didChangeState: newState)
		}
	}
}
