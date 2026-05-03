import Foundation

/// Metadata about the article currently being read aloud, used to populate
/// in-app transport bars and (on iOS) the system now-playing UI.
public struct SpeechItemMetadata: Equatable, Sendable {
	public let articleID: String
	public let title: String
	public let feedName: String?
	public let imageURL: URL?
	public let wordCount: Int

	public init(
		articleID: String,
		title: String,
		feedName: String?,
		imageURL: URL?,
		wordCount: Int
	) {
		self.articleID = articleID
		self.title = title
		self.feedName = feedName
		self.imageURL = imageURL
		self.wordCount = wordCount
	}
}
