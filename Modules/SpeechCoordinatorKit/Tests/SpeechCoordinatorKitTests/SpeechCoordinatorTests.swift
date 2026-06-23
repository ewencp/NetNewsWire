//
//  SpeechCoordinatorTests.swift
//  SpeechCoordinatorKitTests
//

import Testing
import Foundation
import Articles
import ArticleSpeech
@testable import SpeechCoordinatorKit

@MainActor
struct SpeechCoordinatorTests {

	private func makeArticle(id: String, title: String) -> Article {
		Article(
			accountID: "local",
			articleID: id,
			feedID: "feed1",
			uniqueID: id,
			title: title,
			contentHTML: "<p>Body.</p>",
			contentText: nil,
			markdown: nil,
			url: nil,
			externalURL: nil,
			summary: nil,
			imageURL: nil,
			datePublished: nil,
			dateModified: nil,
			authors: nil,
			status: ArticleStatus(articleID: id, read: false, starred: false, dateArrived: Date())
		)
	}

	@Test func startPlaybackInvokesPlayWithBlocksFromHTML() async throws {
		let mock = MockSpeechSynth()
		let coordinator = SpeechCoordinator(synth: mock)
		let article = makeArticle(id: "a1", title: "Title")
		coordinator.startPlayback(
			for: article,
			sourceHTML: "<p>Hello.</p>",
			feedName: "Test Feed",
			imageURL: nil
		)
		// Allow the Task inside startPlayback to drain.
		try await Task.sleep(nanoseconds: 100_000_000)
		#expect(mock.playCount == 1)
		#expect(mock.lastBlocks == [SpeechBlock(text: "Hello.", kind: .paragraph)])
		#expect(coordinator.playingItem?.articleID == "a1")
		#expect(coordinator.playingItem?.title == "Title")
		#expect(coordinator.playingItem?.feedName == "Test Feed")
	}

	@Test func togglePlayPauseWhileSpeakingPauses() {
		let mock = MockSpeechSynth()
		let coordinator = SpeechCoordinator(synth: mock)
		mock.simulateStateChange(.speaking(blockIndex: 0, totalBlocks: 1))
		coordinator.togglePlayPause()
		#expect(mock.pauseCount == 1)
	}

	@Test func togglePlayPauseWhilePausedResumes() {
		let mock = MockSpeechSynth()
		let coordinator = SpeechCoordinator(synth: mock)
		mock.simulateStateChange(.paused(blockIndex: 0, totalBlocks: 1))
		coordinator.togglePlayPause()
		#expect(mock.resumeCount == 1)
	}

	@Test func togglePlayPauseWhileIdleIsNoop() {
		let mock = MockSpeechSynth()
		let coordinator = SpeechCoordinator(synth: mock)
		coordinator.togglePlayPause()
		#expect(mock.pauseCount == 0)
		#expect(mock.resumeCount == 0)
	}

	@Test func finishedClearsPlayingItem() async throws {
		let mock = MockSpeechSynth()
		let coordinator = SpeechCoordinator(synth: mock)
		let article = makeArticle(id: "a1", title: "T")
		coordinator.startPlayback(
			for: article,
			sourceHTML: "<p>X.</p>",
			feedName: nil,
			imageURL: nil
		)
		try await Task.sleep(nanoseconds: 100_000_000)
		mock.simulateStateChange(.finished)
		#expect(coordinator.playingItem == nil)
		#expect(coordinator.state == .finished)
	}

	@Test func observersGetNotifiedOnStateChange() async throws {
		final class TestObserver: SpeechCoordinatorObserver {
			var updateCount = 0
			func speechCoordinatorDidUpdate(_ coordinator: SpeechCoordinator) {
				updateCount += 1
			}
		}
		let mock = MockSpeechSynth()
		let coordinator = SpeechCoordinator(synth: mock)
		let observer = TestObserver()
		coordinator.addObserver(observer)
		mock.simulateStateChange(.speaking(blockIndex: 0, totalBlocks: 1))
		#expect(observer.updateCount == 1)
	}

	@Test func skipForwardForwardsToSynth() {
		let mock = MockSpeechSynth()
		let coordinator = SpeechCoordinator(synth: mock)
		coordinator.skipForward()
		#expect(mock.skipForwardCount == 1)
	}

	@Test func stopForwardsToSynth() {
		let mock = MockSpeechSynth()
		let coordinator = SpeechCoordinator(synth: mock)
		coordinator.stop()
		#expect(mock.stopCount == 1)
	}
}
