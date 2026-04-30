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
		// Lists nest within themselves, which lazy-regex matching can't handle correctly
		// (the first `</ul>` consumed by the outer match is the inner closing tag).
		// We find non-list containers via regex and top-level lists via depth counting,
		// then merge by document position.
		let nonListMatches = findNonListContainerMatches(in: html)
		let listMatches = findTopLevelListMatches(in: html).filter { listMatch in
			!nonListMatches.contains { container in
				NSLocationInRange(listMatch.fullRange.location, container.fullRange)
			}
		}
		// Standalone <img> matches that are NOT inside any container (figures own their imgs).
		let imageMatches = findStandaloneImageMatches(in: html, excluding: nonListMatches)

		struct OrderedMatch {
			let location: Int
			let dispatch: () -> [SpeechContent.Segment]
		}

		var ordered: [OrderedMatch] = []
		for m in nonListMatches {
			ordered.append(OrderedMatch(location: m.fullRange.location) {
				guard let inner = Range(m.contentRange, in: html).map({ String(html[$0]) }) else {
					return []
				}
				return dispatchNonListContainer(tag: m.tag, inner: inner)
			})
		}
		for m in listMatches {
			ordered.append(OrderedMatch(location: m.fullRange.location) {
				guard let inner = Range(m.contentRange, in: html).map({ String(html[$0]) }) else {
					return []
				}
				return extractListItems(from: inner, depth: 0, isOrdered: m.tag == "ol")
			})
		}
		for range in imageMatches {
			ordered.append(OrderedMatch(location: range.location) {
				guard let r = Range(range, in: html) else { return [] }
				let imgTag = String(html[r])
				let src = extractAttribute(from: imgTag, pattern: "src=[\"']([^\"']+)[\"']")
				let alt = extractAttribute(from: imgTag, pattern: "alt=[\"']([^\"']*)[\"']")
				return [.image(SpeechContent.ImageDescriptor(src: src, alt: alt, caption: nil))]
			})
		}
		ordered.sort { $0.location < $1.location }

		var segments: [SpeechContent.Segment] = []
		for m in ordered {
			segments.append(contentsOf: m.dispatch())
		}
		return segments
	}

	private static func findStandaloneImageMatches(
		in html: String,
		excluding containers: [ContainerMatch]
	) -> [NSRange] {
		let pattern = "<img[^>]*>"
		guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
			return []
		}
		return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { m in
			let isNested = containers.contains { container in
				NSLocationInRange(m.range.location, container.fullRange)
			}
			return isNested ? nil : m.range
		}
	}

	private struct ContainerMatch {
		let fullRange: NSRange
		let tag: String
		let contentRange: NSRange
	}

	private static func findNonListContainerMatches(in html: String) -> [ContainerMatch] {
		// Note: `pre` must come before `p` in the alternation. ICU regex tries
		// alternatives left-to-right; if `p` is first, `<pre>` matches as `<p>` plus
		// extra characters, capturing tag="p" and then looking for `</p>` later in the
		// document, which is wrong.
		let pattern = "<(pre|p|h[1-6]|blockquote|figure)[^>]*>([\\s\\S]*?)</\\1>"
		guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
			return []
		}
		return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { m in
			guard let tagRange = Range(m.range(at: 1), in: html) else { return nil }
			let tag = String(html[tagRange]).lowercased()
			return ContainerMatch(fullRange: m.range, tag: tag, contentRange: m.range(at: 2))
		}
	}

	/// Finds top-level `<ul>` and `<ol>` ranges via depth counting. This handles
	/// nested lists correctly (lazy regex would match the first nested `</ul>`).
	private static func findTopLevelListMatches(in html: String) -> [ContainerMatch] {
		let nsHTML = html as NSString
		let openPattern = "<(ul|ol)[^>]*>"
		let closePattern = "</(ul|ol)>"
		guard let openRegex = try? NSRegularExpression(pattern: openPattern, options: .caseInsensitive),
		      let closeRegex = try? NSRegularExpression(pattern: closePattern, options: .caseInsensitive) else {
			return []
		}
		struct Event {
			let position: Int
			let isOpen: Bool
			let tag: String
			let range: NSRange
			let openTagLength: Int
		}
		var events: [Event] = []
		let fullRange = NSRange(location: 0, length: nsHTML.length)
		for m in openRegex.matches(in: html, range: fullRange) {
			let tag = nsHTML.substring(with: m.range(at: 1)).lowercased()
			events.append(Event(
				position: m.range.location,
				isOpen: true,
				tag: tag,
				range: m.range,
				openTagLength: m.range.length
			))
		}
		for m in closeRegex.matches(in: html, range: fullRange) {
			let tag = nsHTML.substring(with: m.range(at: 1)).lowercased()
			events.append(Event(
				position: m.range.location,
				isOpen: false,
				tag: tag,
				range: m.range,
				openTagLength: 0
			))
		}
		events.sort { $0.position < $1.position }

		var stack: [Event] = []
		var results: [ContainerMatch] = []
		for event in events {
			if event.isOpen {
				stack.append(event)
			} else {
				if let opened = stack.last, opened.tag == event.tag {
					stack.removeLast()
					if stack.isEmpty {
						let startLoc = opened.range.location
						let endLoc = event.range.location + event.range.length
						let full = NSRange(location: startLoc, length: endLoc - startLoc)
						let contentStart = opened.range.location + opened.openTagLength
						let contentEnd = event.range.location
						let content = NSRange(location: contentStart, length: contentEnd - contentStart)
						results.append(ContainerMatch(fullRange: full, tag: opened.tag, contentRange: content))
					}
				}
			}
		}
		return results
	}

	private static func dispatchNonListContainer(tag: String, inner: String) -> [SpeechContent.Segment] {
		switch tag {
		case "p":
			return paragraphSegment(from: inner).map { [$0] } ?? []
		case "blockquote":
			return blockQuoteSegment(from: inner).map { [$0] } ?? []
		case "figure":
			return [figureSegment(from: inner)]
		case "pre":
			return [codeBlockSegment(from: inner)]
		default:
			if tag.hasPrefix("h"), let level = Int(tag.dropFirst()) {
				return headingSegment(from: inner, level: level).map { [$0] } ?? []
			}
			return []
		}
	}

	private static func figureSegment(from inner: String) -> SpeechContent.Segment {
		let src = extractAttribute(from: inner, pattern: "src=[\"']([^\"']+)[\"']")
		let alt = extractAttribute(from: inner, pattern: "alt=[\"']([^\"']*)[\"']")
		let captionHTML = extractAttribute(
			from: inner,
			pattern: "<figcaption[^>]*>([\\s\\S]*?)</figcaption>"
		)
		let caption = captionHTML.map {
			decodeHTMLEntities(stripInlineTags($0)).trimmingCharacters(in: .whitespacesAndNewlines)
		}
		return .figure(SpeechContent.ImageDescriptor(src: src, alt: alt, caption: caption))
	}

	private static func codeBlockSegment(from inner: String) -> SpeechContent.Segment {
		let language = extractAttribute(
			from: inner,
			pattern: "class=[\"'][^\"']*language-([a-zA-Z0-9_+\\-]+)[^\"']*[\"']"
		)
		let stripped = stripInlineTags(inner)
		let content = decodeHTMLEntities(stripped).trimmingCharacters(in: .whitespacesAndNewlines)
		return .codeBlock(language: language, content: content)
	}

	private static func extractAttribute(from html: String, pattern: String) -> String? {
		guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
		      let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
		      let range = Range(match.range(at: 1), in: html) else {
			return nil
		}
		return String(html[range])
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

	// MARK: - List extraction (recursive, depth-aware)

	/// Finds top-level `<li>` ranges within a list's content, ignoring `<li>` elements
	/// inside nested `<ul>`/`<ol>`. Lazy regex would match the first inner `</li>`.
	private static func findTopLevelListItemRanges(in html: String) -> [(itemRange: NSRange, contentRange: NSRange, openTagLength: Int)] {
		let nsHTML = html as NSString
		let openListPattern = "<(ul|ol)[^>]*>"
		let closeListPattern = "</(ul|ol)>"
		let openItemPattern = "<li[^>]*>"
		let closeItemPattern = "</li>"
		guard let openListRegex = try? NSRegularExpression(pattern: openListPattern, options: .caseInsensitive),
		      let closeListRegex = try? NSRegularExpression(pattern: closeListPattern, options: .caseInsensitive),
		      let openItemRegex = try? NSRegularExpression(pattern: openItemPattern, options: .caseInsensitive),
		      let closeItemRegex = try? NSRegularExpression(pattern: closeItemPattern, options: .caseInsensitive) else {
			return []
		}
		enum EventKind { case openList, closeList, openItem, closeItem }
		struct Event {
			let position: Int
			let kind: EventKind
			let range: NSRange
		}
		var events: [Event] = []
		let fullRange = NSRange(location: 0, length: nsHTML.length)
		for m in openListRegex.matches(in: html, range: fullRange) {
			events.append(Event(position: m.range.location, kind: .openList, range: m.range))
		}
		for m in closeListRegex.matches(in: html, range: fullRange) {
			events.append(Event(position: m.range.location, kind: .closeList, range: m.range))
		}
		for m in openItemRegex.matches(in: html, range: fullRange) {
			events.append(Event(position: m.range.location, kind: .openItem, range: m.range))
		}
		for m in closeItemRegex.matches(in: html, range: fullRange) {
			events.append(Event(position: m.range.location, kind: .closeItem, range: m.range))
		}
		events.sort { $0.position < $1.position }

		var listDepth = 0
		var openItemAtThisLevel: Event? = nil
		var results: [(itemRange: NSRange, contentRange: NSRange, openTagLength: Int)] = []

		for event in events {
			switch event.kind {
			case .openList:
				listDepth += 1
			case .closeList:
				listDepth -= 1
			case .openItem:
				// Only consider <li>s at the top level of the input (listDepth == 0
				// since we're already inside our list's content; nested <ul>/<ol>
				// pushes us to listDepth > 0).
				if listDepth == 0 {
					openItemAtThisLevel = event
				}
			case .closeItem:
				if listDepth == 0, let opened = openItemAtThisLevel {
					let startLoc = opened.range.location
					let endLoc = event.range.location + event.range.length
					let full = NSRange(location: startLoc, length: endLoc - startLoc)
					let contentStart = opened.range.location + opened.range.length
					let contentEnd = event.range.location
					let content = NSRange(location: contentStart, length: contentEnd - contentStart)
					results.append((full, content, opened.range.length))
					openItemAtThisLevel = nil
				}
			}
		}
		return results
	}

	private static func extractListItems(
		from html: String,
		depth: Int,
		isOrdered: Bool
	) -> [SpeechContent.Segment] {
		let nsHTML = html as NSString
		let itemRanges = findTopLevelListItemRanges(in: html)
		var segments: [SpeechContent.Segment] = []
		var index = 1
		for item in itemRanges {
			let inner = nsHTML.substring(with: item.contentRange)

			// Find nested top-level lists inside this item.
			let nestedListMatches = findTopLevelListMatches(in: inner)

			let textPortion: String
			if let firstNested = nestedListMatches.first {
				let textEnd = firstNested.fullRange.location
				textPortion = (inner as NSString).substring(with: NSRange(location: 0, length: textEnd))
			} else {
				textPortion = inner
			}
			let stripped = stripInlineTags(textPortion)
			let decoded = decodeHTMLEntities(stripped).trimmingCharacters(in: .whitespacesAndNewlines)
			let ordering: SpeechContent.ListOrdering = isOrdered ? .ordered(index: index) : .unordered
			if !decoded.isEmpty {
				segments.append(.listItem(depth: depth, ordering: ordering, decoded))
			}

			// Recurse into any nested lists, in document order.
			for nested in nestedListMatches {
				let nestedInner = (inner as NSString).substring(with: nested.contentRange)
				segments.append(contentsOf: extractListItems(
					from: nestedInner,
					depth: depth + 1,
					isOrdered: nested.tag == "ol"
				))
			}
			index += 1
		}
		return segments
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
