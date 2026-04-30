import Foundation

public enum SpeechBlockBuilder {

	public static func makeBlocks(
		from content: SpeechContent,
		imageRenderer: ImageRenderer = .defaultForImages,
		figureRenderer: ImageRenderer = .defaultForFigures
	) async -> [SpeechBlock] {
		var blocks: [SpeechBlock] = []
		for segment in content.segments {
			switch segment {
			case .paragraph(let text):
				blocks.append(SpeechBlock(text: text, kind: .paragraph))

			case .heading(let level, let text):
				let trimmed = text.hasSuffix(".") ? text : text + "."
				blocks.append(SpeechBlock(text: trimmed, kind: .heading(level: level)))

			case .blockQuote(let text):
				blocks.append(SpeechBlock(text: "Quote: \(text)", kind: .blockQuote))

			case .listItem(let depth, let ordering, let text):
				blocks.append(SpeechBlock(text: text, kind: .listItem(depth: depth, ordering: ordering)))

			case .image(let descriptor):
				let renderedText = await imageRenderer.render(descriptor)
				blocks.append(SpeechBlock(text: renderedText, kind: .imageDescription))

			case .figure(let descriptor):
				let renderedText = await figureRenderer.render(descriptor)
				blocks.append(SpeechBlock(text: renderedText, kind: .figureDescription))

			case .codeBlock(let language, _):
				let text: String
				if let language, !language.isEmpty {
					text = "Code block in \(language) omitted."
				} else {
					text = "Code block omitted."
				}
				blocks.append(SpeechBlock(text: text, kind: .codeNotice))

			case .table(let rowCount, let columnCount):
				let text: String
				if let r = rowCount, let c = columnCount {
					text = "See the \(r)-by-\(c) table in the article."
				} else {
					text = "See table in the article."
				}
				blocks.append(SpeechBlock(text: text, kind: .tableNotice))
			}
		}
		return blocks
	}

	public struct ImageRenderer: Sendable {

		public let render: @Sendable (SpeechContent.ImageDescriptor) async -> String

		public init(render: @escaping @Sendable (SpeechContent.ImageDescriptor) async -> String) {
			self.render = render
		}

		public static let defaultForImages: ImageRenderer = .init { descriptor in
			if let alt = descriptor.alt, !alt.isEmpty {
				return "Image: \(alt)."
			}
			if let caption = descriptor.caption, !caption.isEmpty {
				return "Image: \(caption)."
			}
			return "Image."
		}

		public static let defaultForFigures: ImageRenderer = .init { descriptor in
			if let caption = descriptor.caption, !caption.isEmpty {
				return "Figure: \(caption)."
			}
			if let alt = descriptor.alt, !alt.isEmpty {
				return "Figure: \(alt)."
			}
			return "Figure."
		}
	}
}
