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
struct AudioBufferPlayerSampleTimeTests {

	@Test
	func currentSampleTime_isZeroBeforePlay() {
		let player = AudioBufferPlayer()
		#expect(player.currentSampleTime == 0)
	}

	@Test
	func seekToZero_onIdlePlayer_isNoOp() {
		let player = AudioBufferPlayer()
		player.seek(toSampleTime: 0)
		#expect(player.currentSampleTime == 0)
	}

	@Test
	func seekToExactBufferBoundary_setsCurrentSampleTime() {
		let player = AudioBufferPlayer()
		let buf1 = makeSilenceBuffer(seconds: 1.0)  // 22050 frames at 22050Hz
		let buf2 = makeSilenceBuffer(seconds: 1.0)
		player.enqueue(buf1)
		player.enqueue(buf2)
		player.seek(toSampleTime: 22050)
		// Seeking to exactly the boundary between buf1 and buf2 — frame 22050 is
		// the first frame of buf2. Without play() called, currentSampleTime reads
		// from seekBaseline.
		#expect(player.currentSampleTime == 22050)
	}

	@Test
	func seekBeyondLastBuffer_setsBaselineButLeavesNothingScheduled() {
		let player = AudioBufferPlayer()
		let buf1 = makeSilenceBuffer(seconds: 1.0)
		player.enqueue(buf1)
		// Seek past the end of all known buffers.
		player.seek(toSampleTime: 50000)
		#expect(player.currentSampleTime == 50000)
	}

	@Test
	func seekIntoMiddleOfBuffer_keepsBaselineAtSeekTarget() {
		let player = AudioBufferPlayer()
		let buf1 = makeSilenceBuffer(seconds: 1.0)  // 22050 frames
		player.enqueue(buf1)
		player.seek(toSampleTime: 11025)  // halfway through buf1
		#expect(player.currentSampleTime == 11025)
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
