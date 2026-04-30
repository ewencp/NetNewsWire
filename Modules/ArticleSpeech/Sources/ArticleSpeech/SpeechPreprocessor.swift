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

		let segments = extractSegmentsInOrder(from: text)

		return SpeechContent(
			segments: segments,
			title: title,
			language: language,
			sourceArticleID: articleID
		)
	}

	// MARK: - Unified walker (extended in later tasks)

	private static func extractSegmentsInOrder(from html: String) -> [SpeechContent.Segment] {
		// Pattern matches any block-level container element we care about.
		// Capture group 1: tag name; group 2: full content (lazy match).
		let pattern = "<(p|h[1-6]|blockquote)[^>]*>([\\s\\S]*?)</\\1>"
		guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
			return []
		}
		var segments: [SpeechContent.Segment] = []
		let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
		for match in matches {
			guard let tagRange = Range(match.range(at: 1), in: html),
			      let contentRange = Range(match.range(at: 2), in: html) else {
				continue
			}
			let tag = String(html[tagRange]).lowercased()
			let inner = String(html[contentRange])

			switch tag {
			case "p":
				if let segment = paragraphSegment(from: inner) {
					segments.append(segment)
				}
			case "blockquote":
				if let segment = blockQuoteSegment(from: inner) {
					segments.append(segment)
				}
			default:
				if tag.hasPrefix("h"), let level = Int(tag.dropFirst()) {
					if let segment = headingSegment(from: inner, level: level) {
						segments.append(segment)
					}
				}
			}
		}
		return segments
	}

	// MARK: - Per-tag dispatch helpers

	private static func paragraphSegment(from inner: String) -> SpeechContent.Segment? {
		let stripped = stripInlineTags(inner)
		let decoded = decodeHTMLEntities(stripped).trimmingCharacters(in: .whitespacesAndNewlines)
		return decoded.isEmpty ? nil : .paragraph(decoded)
	}

	private static func blockQuoteSegment(from inner: String) -> SpeechContent.Segment? {
		let stripped = stripInlineTags(inner)
		let decoded = decodeHTMLEntities(stripped).trimmingCharacters(in: .whitespacesAndNewlines)
		return decoded.isEmpty ? nil : .blockQuote(decoded)
	}

	private static func headingSegment(from inner: String, level: Int) -> SpeechContent.Segment? {
		let stripped = stripInlineTags(inner)
		let decoded = decodeHTMLEntities(stripped).trimmingCharacters(in: .whitespacesAndNewlines)
		return decoded.isEmpty ? nil : .heading(level: level, decoded)
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
