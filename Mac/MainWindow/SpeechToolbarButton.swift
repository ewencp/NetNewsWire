//
//  SpeechToolbarButton.swift
//  NetNewsWire
//

import AppKit

enum SpeechToolbarButtonState {
	case off
	case preparing
	case playing
	case paused
	case error
}

final class SpeechToolbarButton: NSButton {

	private let progressIndicator: NSProgressIndicator = {
		let indicator = NSProgressIndicator()
		indicator.style = .spinning
		indicator.controlSize = .small
		indicator.isDisplayedWhenStopped = false
		indicator.translatesAutoresizingMaskIntoConstraints = false
		return indicator
	}()

	var buttonState: SpeechToolbarButtonState = .off {
		didSet {
			if buttonState != oldValue {
				refreshAppearance()
			}
		}
	}

	override func accessibilityLabel() -> String? {
		switch buttonState {
		case .off:        return NSLocalizedString("Speak Article", comment: "Speak Article")
		case .preparing:  return NSLocalizedString("Preparing speech", comment: "Preparing speech")
		case .playing:    return NSLocalizedString("Pause speech", comment: "Pause speech")
		case .paused:     return NSLocalizedString("Resume speech", comment: "Resume speech")
		case .error:      return NSLocalizedString("Speech error", comment: "Speech error")
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
		imageScaling = .scaleProportionallyDown
		widthAnchor.constraint(equalTo: heightAnchor).isActive = true

		addSubview(progressIndicator)
		NSLayoutConstraint.activate([
			progressIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
			progressIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
		])
		refreshAppearance()
	}

	private func refreshAppearance() {
		switch buttonState {
		case .off:
			progressIndicator.stopAnimation(nil)
			isEnabled = true
			image = NSImage(systemSymbolName: "play.circle", accessibilityDescription: nil)
		case .preparing:
			image = nil
			progressIndicator.startAnimation(nil)
			isEnabled = false
		case .playing:
			progressIndicator.stopAnimation(nil)
			isEnabled = true
			image = NSImage(systemSymbolName: "pause.circle.fill", accessibilityDescription: nil)
		case .paused:
			progressIndicator.stopAnimation(nil)
			isEnabled = true
			image = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: nil)
		case .error:
			progressIndicator.stopAnimation(nil)
			isEnabled = true
			image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
		}
	}
}
