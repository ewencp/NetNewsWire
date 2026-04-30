import Foundation

public struct SpeechVoice: Sendable, Equatable, Hashable {

	public let identifier: String
	public let displayName: String
	public let language: String
	public let qualityTier: QualityTier
	public let gender: VoiceGender
	public let isInstalled: Bool

	public init(
		identifier: String,
		displayName: String,
		language: String,
		qualityTier: QualityTier,
		gender: VoiceGender,
		isInstalled: Bool
	) {
		self.identifier = identifier
		self.displayName = displayName
		self.language = language
		self.qualityTier = qualityTier
		self.gender = gender
		self.isInstalled = isInstalled
	}

	public enum QualityTier: Sendable, Equatable, Hashable, Comparable {
		case standard
		case enhanced
		case premium
	}
}

public enum VoiceGender: Sendable, Equatable, Hashable {
	case female
	case male
	case neutral
	case unspecified
}
