import Foundation

public enum SpeechPreprocessor {

	public static func preprocess(
		html: String,
		articleID: String,
		title: String?,
		language: String?
	) -> SpeechContent {
		guard !html.isEmpty else {
			return SpeechContent(segments: [], title: title, language: language, sourceArticleID: articleID)
		}

		var text = html

		// Strip non-content tags and their contents.
		let stripTags = ["script", "style", "nav", "iframe", "form", "noscript"]
		for tag in stripTags {
			text = stripTagWithContent(text, tag: tag)
		}

		var segments: [SpeechContent.Segment] = []
		extractParagraphs(from: text, into: &segments)

		return SpeechContent(
			segments: segments,
			title: title,
			language: language,
			sourceArticleID: articleID
		)
	}

	// MARK: - Extraction (incremental; more added in later tasks)

	private static func extractParagraphs(from html: String, into segments: inout [SpeechContent.Segment]) {
		let pattern = "<p[^>]*>([\\s\\S]*?)</p>"
		guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
			return
		}
		let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
		for match in matches {
			guard let contentRange = Range(match.range(at: 1), in: html) else { continue }
			let inner = String(html[contentRange])
			let stripped = stripInlineTags(inner)
			let decoded = decodeHTMLEntities(stripped).trimmingCharacters(in: .whitespacesAndNewlines)
			if !decoded.isEmpty {
				segments.append(.paragraph(decoded))
			}
		}
	}

	// MARK: - Helpers

	internal static func stripInlineTags(_ html: String) -> String {
		html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
	}

	internal static func stripTagWithContent(_ html: String, tag: String) -> String {
		let pattern = "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>"
		return html.replacingOccurrences(
			of: pattern,
			with: "",
			options: [.regularExpression, .caseInsensitive]
		)
	}

	internal static func decodeHTMLEntities(_ text: String) -> String {
		guard text.contains("&") else { return text }

		var result = text
		let entities: [(String, String)] = [
			("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
			("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"),
			("&mdash;", "\u{2014}"), ("&ndash;", "\u{2013}"),
			("&nbsp;", " "), ("&hellip;", "\u{2026}"),
			("&laquo;", "\u{00AB}"), ("&raquo;", "\u{00BB}"),
			("&bull;", "\u{2022}"), ("&middot;", "\u{00B7}"),
			("&copy;", "\u{00A9}"), ("&reg;", "\u{00AE}"),
			("&trade;", "\u{2122}"),
		]
		for (entity, char) in entities {
			result = result.replacingOccurrences(of: entity, with: char)
		}

		if let numericRegex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
			let matches = numericRegex.matches(in: result, range: NSRange(result.startIndex..., in: result))
			for match in matches.reversed() {
				guard let fullRange = Range(match.range, in: result),
				      let hexRange = Range(match.range(at: 1), in: result),
				      let valueRange = Range(match.range(at: 2), in: result) else {
					continue
				}
				let isHex = !result[hexRange].isEmpty
				let valueStr = String(result[valueRange])
				let codePoint: UInt32? = isHex ? UInt32(valueStr, radix: 16) : UInt32(valueStr, radix: 10)
				if let cp = codePoint, let scalar = Unicode.Scalar(cp) {
					result = result.replacingCharacters(in: fullRange, with: String(scalar))
				}
			}
		}

		return result
	}
}
