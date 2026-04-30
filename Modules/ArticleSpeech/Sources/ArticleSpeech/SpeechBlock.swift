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
