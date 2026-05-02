import Foundation
import Tidemark

/// Converts LLM markdown output to rendered HTML, rehydrating image references.
public enum SummaryPostprocessor {

	/// Converts a markdown summary with `[Image N]` references back to HTML.
	///
	/// - Parameters:
	///   - markdown: The LLM's markdown response.
	///   - imageReferences: The numbered lookup table from preprocessing.
	/// - Returns: Rendered HTML ready for display in the article detail view.
	public static func postprocess(markdown: String, imageReferences: [Int: ImageReference]) -> String {
		guard !markdown.isEmpty else {
			return ""
		}

		// 1. Rehydrate image references before markdown conversion
		var text = rehydrateImages(in: markdown, references: imageReferences)

		// 2. Convert markdown to HTML
		text = Tidemark.markdownToHTML(text)

		return text
	}

	// MARK: - Private

	/// Matches `[Image N]` and `[Image N: any description text]`
	private static let imageRefPattern = "\\[Image (\\d+)(?::[^\\]]*)?\\]"

	private static func rehydrateImages(in markdown: String, references: [Int: ImageReference]) -> String {
		guard let regex = try? NSRegularExpression(pattern: imageRefPattern, options: []) else {
			return markdown
		}

		var result = markdown
		let matches = regex.matches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown))

		for match in matches.reversed() {
			guard let fullRange = Range(match.range, in: result),
				  let numberRange = Range(match.range(at: 1), in: result),
				  let imageNumber = Int(result[numberRange]),
				  let ref = references[imageNumber] else {
				continue
			}

			let imgHTML = buildImageHTML(for: ref)
			result = result.replacingCharacters(in: fullRange, with: imgHTML)
		}

		return result
	}

	private static func buildImageHTML(for ref: ImageReference) -> String {
		var imgTag = "<img src=\"\(ref.src)\""
		if let alt = ref.alt {
			imgTag += " alt=\"\(alt)\""
		}
		imgTag += ">"

		if let caption = ref.caption {
			return "<figure>\(imgTag)<figcaption>\(caption)</figcaption></figure>"
		}

		return imgTag
	}
}
