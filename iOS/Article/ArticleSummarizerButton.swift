//
//  ArticleSummarizerButton.swift
//  NetNewsWire-iOS
//

import UIKit

enum ArticleSummarizerButtonState {
	case error
	case animated
	case on
	case off
}

final class ArticleSummarizerButton: UIButton {

	private let activityIndicator: UIActivityIndicatorView = {
		let indicator = UIActivityIndicatorView(style: .medium)
		indicator.hidesWhenStopped = true
		indicator.translatesAutoresizingMaskIntoConstraints = false
		return indicator
	}()

	var buttonState: ArticleSummarizerButtonState = .off {
		didSet {
			if buttonState != oldValue {
				switch buttonState {
				case .error:
					activityIndicator.stopAnimating()
					isUserInteractionEnabled = true
					setImage(Assets.Images.articleSummarizerError, for: .normal)
				case .animated:
					setImage(nil, for: .normal)
					activityIndicator.startAnimating()
					isUserInteractionEnabled = false
				case .on:
					activityIndicator.stopAnimating()
					isUserInteractionEnabled = true
					setImage(Assets.Images.articleSummarizerOn, for: .normal)
				case .off:
					activityIndicator.stopAnimating()
					isUserInteractionEnabled = true
					setImage(Assets.Images.articleSummarizerOff, for: .normal)
				}
			}
		}
	}

	override var accessibilityLabel: String? {
		get {
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
		set {
			super.accessibilityLabel = newValue
		}
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
		setImage(Assets.Images.articleSummarizerOff, for: .normal)
		addSubview(activityIndicator)
		NSLayoutConstraint.activate([
			widthAnchor.constraint(equalToConstant: 44.0),
			activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
			activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
		])
	}
}
