//
//  ArticleSummarizerButton.swift
//  NetNewsWire
//

import AppKit

enum ArticleSummarizerButtonState {
	case error
	case animated
	case on
	case off
}

final class ArticleSummarizerButton: NSButton {

	private let progressIndicator: NSProgressIndicator = {
		let indicator = NSProgressIndicator()
		indicator.style = .spinning
		indicator.controlSize = .small
		indicator.isDisplayedWhenStopped = false
		indicator.translatesAutoresizingMaskIntoConstraints = false
		return indicator
	}()

	var buttonState: ArticleSummarizerButtonState = .off {
		didSet {
			if buttonState != oldValue {
				switch buttonState {
				case .error:
					progressIndicator.stopAnimation(nil)
					isEnabled = true
					image = Assets.Images.articleSummarizerError
				case .animated:
					image = nil
					progressIndicator.startAnimation(nil)
					isEnabled = false
				case .on:
					progressIndicator.stopAnimation(nil)
					isEnabled = true
					image = Assets.Images.articleSummarizerOn
				case .off:
					progressIndicator.stopAnimation(nil)
					isEnabled = true
					image = Assets.Images.articleSummarizerOff
				}
			}
		}
	}

	override func accessibilityLabel() -> String? {
		switch buttonState {
		case .error:
			return NSLocalizedString("Error - Summarize", comment: "Error - Summarize")
		case .animated:
			return NSLocalizedString("Summarizing", comment: "Summarizing")
		case .on:
			return NSLocalizedString("Selected - Summarize", comment: "Selected - Summarize")
		case .off:
			return NSLocalizedString("Summarize", comment: "Summarize")
		}
	}

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		commonInit()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}

	private func commonInit() {
		wantsLayer = true
		bezelStyle = .texturedRounded
		image = Assets.Images.articleSummarizerOff
		imageScaling = .scaleProportionallyDown
		widthAnchor.constraint(equalTo: heightAnchor).isActive = true

		addSubview(progressIndicator)
		NSLayoutConstraint.activate([
			progressIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
			progressIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
		])
	}
}
