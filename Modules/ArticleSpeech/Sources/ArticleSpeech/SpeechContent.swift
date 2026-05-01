import Foundation

public struct SpeechContent: Sendable {

	public let segments: [Segment]
	public let title: String?
	public let language: String?
	public let sourceArticleID: String

	public init(segments: [Segment], title: String?, language: String?, sourceArticleID: String) {
		self.segments = segments
		self.title = title
		self.language = language
		self.sourceArticleID = sourceArticleID
	}

	public enum Segment: Sendable, Equatable {
		case paragraph(String)
		case heading(level: Int, String)
		case blockQuote(String)
		case listItem(depth: Int, ordering: ListOrdering, String)
		case image(ImageDescriptor)
		case figure(ImageDescriptor)
		case codeBlock(language: String?, content: String)
		case table(rowCount: Int?, columnCount: Int?)
	}

	public enum ListOrdering: Sendable, Equatable {
		case unordered
		case ordered(index: Int)
	}

	public struct ImageDescriptor: Sendable, Equatable {
		public let src: String?
		public let alt: String?
		public let caption: String?

		public init(src: String?, alt: String?, caption: String?) {
			self.src = src
			self.alt = alt
			self.caption = caption
		}
	}
}
