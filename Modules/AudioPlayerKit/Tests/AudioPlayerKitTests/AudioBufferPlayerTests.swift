import Testing
import AVFoundation
@testable import AudioPlayerKit

@MainActor
struct AudioBufferPlayerTransportTests {

	@Test
	func initialState_isIdle() {
		let player = AudioBufferPlayer()
		#expect(player.state == .idle)
	}

	@Test
	func enqueueWithoutPlay_doesNotStartPlayback() {
		let player = AudioBufferPlayer()
		let buffer = makeSilenceBuffer(seconds: 0.1)
		player.enqueue(buffer)
		#expect(player.state == .idle)
	}

	@Test
	func playWithEnqueuedBuffer_transitionsToPlaying() {
		let player = AudioBufferPlayer()
		let buffer = makeSilenceBuffer(seconds: 0.1)
		player.enqueue(buffer)
		player.play()
		#expect(player.state == .playing)
	}

	@Test
	func playWithoutEnqueue_transitionsToPreparing() {
		let player = AudioBufferPlayer()
		player.play()
		#expect(player.state == .preparing)
	}

	@Test
	func stop_returnsToIdle() {
		let player = AudioBufferPlayer()
		let buffer = makeSilenceBuffer(seconds: 0.1)
		player.enqueue(buffer)
		player.play()
		player.stop()
		#expect(player.state == .idle)
	}

	@Test
	func stateChange_notifiesObserver() {
		let player = AudioBufferPlayer()
		let recorder = ObserverRecorder()
		player.addObserver(recorder)

		let buffer = makeSilenceBuffer(seconds: 0.1)
		player.enqueue(buffer)
		player.play()

		#expect(recorder.observedStates.contains(.playing) || recorder.observedStates.contains(.preparing))
	}
}

@MainActor
final class ObserverRecorder: AudioBufferPlayerObserver {
	var observedStates: [AudioBufferPlayerState] = []

	func audioBufferPlayer(_ player: AudioBufferPlayer, didChangeState state: AudioBufferPlayerState) {
		observedStates.append(state)
	}

	func audioBufferPlayer(_ player: AudioBufferPlayer, didAdvanceTo sampleTime: AVAudioFramePosition) {
		// Not exercised in transport tests.
	}
}

@MainActor
private func makeSilenceBuffer(seconds: Double, sampleRate: Double = 22050) -> AVAudioPCMBuffer {
	let format = AVAudioFormat(
		commonFormat: .pcmFormatFloat32,
		sampleRate: sampleRate,
		channels: 1,
		interleaved: false
	)!
	let frameCount = AVAudioFrameCount(seconds * sampleRate)
	let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
	buffer.frameLength = frameCount
	return buffer
}
