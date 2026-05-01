//
//  SpeechToolbarButton.swift
//  NetNewsWire-iOS
//

import UIKit

enum SpeechToolbarButtonState {
	case off
	case preparing
	case playing
	case paused
	case error
}

final class SpeechToolbarButton: UIButton {

	private let activityIndicator: UIActivityIndicatorView = {
		let indicator = UIActivityIndicatorView(style: .medium)
		indicator.hidesWhenStopped = true
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

	override var accessibilityLabel: String? {
		get {
			switch buttonState {
			case .off:        return NSLocalizedString("Speak Article", comment: "Speak Article")
			case .preparing:  return NSLocalizedString("Preparing speech", comment: "Preparing speech")
			case .playing:    return NSLocalizedString("Pause speech", comment: "Pause speech")
			case .paused:     return NSLocalizedString("Resume speech", comment: "Resume speech")
			case .error:      return NSLocalizedString("Speech error", comment: "Speech error")
			}
		}
		set { super.accessibilityLabel = newValue }
	}

	override init(frame: CGRect) {
		super.init(frame: frame)
		commonInit()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}

	private func commonInit() {
		addSubview(activityIndicator)
		NSLayoutConstraint.activate([
			widthAnchor.constraint(equalToConstant: 44.0),
			activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
			activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
		])
		refreshAppearance()
	}

	private func refreshAppearance() {
		switch buttonState {
		case .off:
			activityIndicator.stopAnimating()
			isUserInteractionEnabled = true
			setImage(UIImage(systemName: "play.circle"), for: .normal)
		case .preparing:
			setImage(nil, for: .normal)
			activityIndicator.startAnimating()
			isUserInteractionEnabled = false
		case .playing:
			activityIndicator.stopAnimating()
			isUserInteractionEnabled = true
			setImage(UIImage(systemName: "pause.circle.fill"), for: .normal)
		case .paused:
			activityIndicator.stopAnimating()
			isUserInteractionEnabled = true
			setImage(UIImage(systemName: "play.circle.fill"), for: .normal)
		case .error:
			activityIndicator.stopAnimating()
			isUserInteractionEnabled = true
			setImage(UIImage(systemName: "exclamationmark.triangle"), for: .normal)
		}
	}
}
