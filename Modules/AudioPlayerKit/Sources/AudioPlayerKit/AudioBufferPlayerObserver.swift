import Foundation
import AVFoundation

@MainActor
public protocol AudioBufferPlayerObserver: AnyObject {
	func audioBufferPlayer(_ player: AudioBufferPlayer, didChangeState state: AudioBufferPlayerState)
	func audioBufferPlayer(_ player: AudioBufferPlayer, didAdvanceTo sampleTime: AVAudioFramePosition)
}
