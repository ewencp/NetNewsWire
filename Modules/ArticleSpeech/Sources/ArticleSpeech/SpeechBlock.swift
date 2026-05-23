import Foundation

public struct SpeechBlock: Sendable, Equatable {

	public let text: String
	public let kind: Kind

	public init(text: String, kind: Kind) {
		self.text = text
		self.kind = kind
	}

	public enum Kind: Sendable, Equatable {
		case paragraph
		case heading(level: Int)
		case blockQuote
		case listItem(depth: Int, ordering: SpeechContent.ListOrdering)
		case imageDescription
		case figureDescription
		case codeNotice
		case tableNotice
	}
}

public extension SpeechBlock.Kind {

	/// Seconds of silence to insert before the spoken block.
	///
	/// Backend-agnostic: synthesizer implementations consume this to size
	/// pre-utterance silence (whether via `AVSpeechUtterance.preUtteranceDelay`
	/// for the legacy path or by enqueueing a silence PCM buffer in the
	/// `AVSpeechSynthesizer.write` path). Keeping the timing colocated with
	/// the enum lets all speech backends share a single source of truth.
	var preUtteranceDelay: TimeInterval {
		switch self {
		case .heading: return 0.4
		case .blockQuote: return 0.3
		case .imageDescription, .figureDescription, .codeNotice, .tableNotice: return 0.2
		case .paragraph, .listItem: return 0
		}
	}

	/// Seconds of silence to insert after the spoken block.
	var postUtteranceDelay: TimeInterval {
		switch self {
		case .heading: return 0.5
		case .paragraph: return 0.3
		case .blockQuote: return 0.4
		case .imageDescription, .figureDescription, .codeNotice, .tableNotice: return 0.3
		case .listItem: return 0.15
		}
	}
}
