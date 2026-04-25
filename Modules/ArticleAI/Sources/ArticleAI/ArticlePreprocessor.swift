import Foundation

/// Reference to an image extracted during preprocessing.
public struct ImageReference: Equatable, Sendable {

	public let src: String
	public let alt: String?
	public let caption: String?

	public init(src: String, alt: String? = nil, caption: String? = nil) {
		self.src = src
		self.alt = alt
		self.caption = caption
	}
}

/// Result of preprocessing article HTML for summarization.
public struct ArticlePreprocessingResult: Sendable {

	/// Article content converted to markdown-ish plain text.
	public let markdownText: String

	/// Numbered image references extracted from the HTML (1-indexed).
	public let imageReferences: [Int: ImageReference]

	public init(markdownText: String, imageReferences: [Int: ImageReference]) {
		self.markdownText = markdownText
		self.imageReferences = imageReferences
	}
}

/// Converts article HTML into clean text suitable for LLM summarization.
///
/// Strips non-content elements, extracts images into numbered references,
/// converts structural HTML to lightweight markdown-style text, and
/// decodes HTML entities.
public enum ArticlePreprocessor {

	public static func preprocess(_ html: String) -> ArticlePreprocessingResult {
		guard !html.isEmpty else {
			return ArticlePreprocessingResult(markdownText: "", imageReferences: [:])
		}

		var text = html
		var imageRefs: [Int: ImageReference] = [:]
		var imageCounter = 0

		// 1. Remove non-content block elements and their contents
		let stripTags = ["script", "style", "nav", "iframe", "form", "noscript"]
		for tag in stripTags {
			text = stripTagWithContent(text, tag: tag)
		}

		// 2. Extract <figure> elements (before standalone <img> to avoid double-counting)
		text = extractFigures(text, refs: &imageRefs, counter: &imageCounter)

		// 3. Extract standalone <img> elements
		text = extractImages(text, refs: &imageRefs, counter: &imageCounter)

		// 4. Convert structural HTML to markdown

		// Line breaks (before paragraphs, so <br> inside <p> converts first)
		text = text.replacingOccurrences(
			of: "<br\\s*/?>",
			with: "\n",
			options: .regularExpression
		)

		// Headings
		for level in 1...6 {
			let prefix = String(repeating: "#", count: level)
			text = replaceTag(text, tag: "h\(level)", replacement: { content in
				"\n\n\(prefix) \(content.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
			})
		}

		// Blockquotes
		text = replaceTag(text, tag: "blockquote", replacement: { content in
			let lines = content.trimmingCharacters(in: .whitespacesAndNewlines)
				.components(separatedBy: .newlines)
				.map { "> \($0)" }
				.joined(separator: "\n")
			return "\n\n\(lines)\n\n"
		})

		// List items
		text = replaceTag(text, tag: "li", replacement: { content in
			"- \(content.trimmingCharacters(in: .whitespacesAndNewlines))\n"
		})

		// Remove list wrappers but keep content
		text = replaceTag(text, tag: "ul", replacement: { content in "\n\(content)\n" })
		text = replaceTag(text, tag: "ol", replacement: { content in "\n\(content)\n" })

		// Paragraphs
		text = replaceTag(text, tag: "p", replacement: { content in
			"\n\n\(content.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
		})

		// 5. Strip all remaining HTML tags
		text = text.replacingOccurrences(
			of: "<[^>]+>",
			with: "",
			options: .regularExpression
		)

		// 6. Decode HTML entities
		text = decodeHTMLEntities(text)

		// 7. Clean up whitespace: collapse runs of 3+ newlines to 2
		text = text.replacingOccurrences(
			of: "\\n{3,}",
			with: "\n\n",
			options: .regularExpression
		)
		text = text.trimmingCharacters(in: .whitespacesAndNewlines)

		return ArticlePreprocessingResult(markdownText: text, imageReferences: imageRefs)
	}

	// MARK: - Private Helpers

	private static func stripTagWithContent(_ html: String, tag: String) -> String {
		let pattern = "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>"
		return html.replacingOccurrences(
			of: pattern,
			with: "",
			options: [.regularExpression, .caseInsensitive]
		)
	}

	private static func extractFigures(
		_ html: String,
		refs: inout [Int: ImageReference],
		counter: inout Int
	) -> String {
		let figurePattern = "<figure[^>]*>([\\s\\S]*?)</figure>"
		let imgSrcPattern = "src=[\"']([^\"']+)[\"']"
		let imgAltPattern = "alt=[\"']([^\"']*)[\"']"
		let captionPattern = "<figcaption[^>]*>([\\s\\S]*?)</figcaption>"

		guard let figureRegex = try? NSRegularExpression(pattern: figurePattern, options: .caseInsensitive) else {
			return html
		}

		let matches = figureRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))

		// Assign numbers in forward (document) order
		var numbered: [(match: NSTextCheckingResult, number: Int)] = []
		for match in matches {
			let fullMatch = String(html[Range(match.range, in: html)!])
			let src = extractAttribute(from: fullMatch, pattern: imgSrcPattern)
			guard src != nil else {
				continue
			}
			counter += 1
			numbered.append((match, counter))
		}

		// Apply replacements in reverse order to preserve ranges
		var result = html
		for (match, number) in numbered.reversed() {
			guard let fullRange = Range(match.range, in: result) else {
				continue
			}

			let fullMatch = String(result[fullRange])

			let src = extractAttribute(from: fullMatch, pattern: imgSrcPattern)!
			let alt = extractAttribute(from: fullMatch, pattern: imgAltPattern)
			let captionHTML = extractAttribute(from: fullMatch, pattern: captionPattern)
			let caption = captionHTML.map { stripHTMLTags($0).trimmingCharacters(in: .whitespacesAndNewlines) }

			refs[number] = ImageReference(src: src, alt: alt, caption: caption)

			let placeholder = buildImagePlaceholder(number: number, alt: alt, caption: caption)
			result = result.replacingCharacters(in: fullRange, with: "\n\(placeholder)\n")
		}

		return result
	}

	private static func extractImages(
		_ html: String,
		refs: inout [Int: ImageReference],
		counter: inout Int
	) -> String {
		let imgPattern = "<img[^>]*>"
		let srcPattern = "src=[\"']([^\"']+)[\"']"
		let altPattern = "alt=[\"']([^\"']*)[\"']"

		guard let imgRegex = try? NSRegularExpression(pattern: imgPattern, options: .caseInsensitive) else {
			return html
		}

		let matches = imgRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))

		// Assign numbers in forward (document) order
		var numbered: [(match: NSTextCheckingResult, number: Int)] = []
		for match in matches {
			let imgTag = String(html[Range(match.range, in: html)!])
			guard extractAttribute(from: imgTag, pattern: srcPattern) != nil else {
				continue
			}
			counter += 1
			numbered.append((match, counter))
		}

		// Apply replacements in reverse order to preserve ranges
		var result = html
		for (match, number) in numbered.reversed() {
			guard let fullRange = Range(match.range, in: result) else {
				continue
			}

			let imgTag = String(result[fullRange])
			let src = extractAttribute(from: imgTag, pattern: srcPattern)!
			let alt = extractAttribute(from: imgTag, pattern: altPattern)

			refs[number] = ImageReference(src: src, alt: alt)

			let placeholder = buildImagePlaceholder(number: number, alt: alt, caption: nil)
			result = result.replacingCharacters(in: fullRange, with: placeholder)
		}

		return result
	}

	private static func buildImagePlaceholder(number: Int, alt: String?, caption: String?) -> String {
		var placeholder = "[Image \(number)"
		if let alt, !alt.isEmpty {
			placeholder += ": \(alt)"
			if let caption, !caption.isEmpty {
				placeholder += " | Caption: \(caption)"
			}
		} else if let caption, !caption.isEmpty {
			placeholder += ": \(caption)"
		}
		placeholder += "]"
		return placeholder
	}

	private static func extractAttribute(from html: String, pattern: String) -> String? {
		guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
			  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
			  let range = Range(match.range(at: 1), in: html) else {
			return nil
		}
		return String(html[range])
	}

	private static func replaceTag(_ html: String, tag: String, replacement: (String) -> String) -> String {
		let pattern = "<\(tag)[^>]*>([\\s\\S]*?)</\(tag)>"
		guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
			return html
		}

		var result = html
		let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))

		for match in matches.reversed() {
			guard let fullRange = Range(match.range, in: result),
				  let contentRange = Range(match.range(at: 1), in: result) else {
				continue
			}
			let content = String(result[contentRange])
			result = result.replacingCharacters(in: fullRange, with: replacement(content))
		}

		return result
	}

	private static func stripHTMLTags(_ html: String) -> String {
		html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
	}

	private static func decodeHTMLEntities(_ text: String) -> String {
		guard text.contains("&") else {
			return text
		}

		// Handle common entities manually (avoids NSAttributedString overhead
		// and cross-platform issues with DocumentType.html)
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

		// Handle numeric entities: &#NNN; and &#xHHH;
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
				let codePoint: UInt32?
				if isHex {
					codePoint = UInt32(valueStr, radix: 16)
				} else {
					codePoint = UInt32(valueStr, radix: 10)
				}
				if let cp = codePoint, let scalar = Unicode.Scalar(cp) {
					result = result.replacingCharacters(in: fullRange, with: String(scalar))
				}
			}
		}

		return result
	}
}
