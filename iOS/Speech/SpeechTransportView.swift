//
//  SpeechTransportView.swift
//  NetNewsWire-iOS
//

import UIKit
import ArticleSpeech
import SpeechCoordinatorKit

@MainActor
protocol SpeechTransportViewDelegate: AnyObject {
	func speechTransportViewDidTapTitle(_ view: SpeechTransportView)
}

final class SpeechTransportView: UIView {

	weak var delegate: SpeechTransportViewDelegate?

	private let topSeparator: UIView = {
		let view = UIView()
		view.backgroundColor = .separator
		view.translatesAutoresizingMaskIntoConstraints = false
		return view
	}()

	private let titleButton: UIButton = {
		let button = UIButton(type: .system)
		button.titleLabel?.lineBreakMode = .byTruncatingTail
		button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
		button.titleLabel?.adjustsFontForContentSizeCategory = true
		button.contentHorizontalAlignment = .center
		button.setTitleColor(.label, for: .normal)
		button.translatesAutoresizingMaskIntoConstraints = false
		return button
	}()

	private let progressView: UIProgressView = {
		let bar = UIProgressView(progressViewStyle: .default)
		bar.translatesAutoresizingMaskIntoConstraints = false
		return bar
	}()

	private let stopButton = UIButton(type: .system)
	private let skipBackwardButton = UIButton(type: .system)
	private let playPauseButton = UIButton(type: .system)
	private let skipForwardButton = UIButton(type: .system)

	override init(frame: CGRect) {
		super.init(frame: frame)
		commonInit()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}

	private func commonInit() {
		backgroundColor = .secondarySystemBackground

		titleButton.addTarget(self, action: #selector(titleTapped(_:)), for: .touchUpInside)
		addSubview(topSeparator)
		addSubview(titleButton)
		addSubview(progressView)

		setupControlButton(stopButton, symbol: "xmark", action: #selector(stopTapped(_:)), pointSize: 14)
		setupControlButton(skipBackwardButton, symbol: "backward.fill", action: #selector(skipBackwardTapped(_:)), pointSize: 18)
		setupControlButton(playPauseButton, symbol: "play.fill", action: #selector(playPauseTapped(_:)), pointSize: 24)
		setupControlButton(skipForwardButton, symbol: "forward.fill", action: #selector(skipForwardTapped(_:)), pointSize: 18)

		let controlsStack = UIStackView(arrangedSubviews: [skipBackwardButton, playPauseButton, skipForwardButton])
		controlsStack.axis = .horizontal
		controlsStack.spacing = 32
		controlsStack.alignment = .center
		controlsStack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(controlsStack)
		addSubview(stopButton)
		stopButton.translatesAutoresizingMaskIntoConstraints = false

		NSLayoutConstraint.activate([
			topSeparator.topAnchor.constraint(equalTo: topAnchor),
			topSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
			topSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
			topSeparator.heightAnchor.constraint(equalToConstant: 0.5),

			titleButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
			titleButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
			titleButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

			progressView.topAnchor.constraint(equalTo: titleButton.bottomAnchor, constant: 8),
			progressView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
			progressView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

			stopButton.centerYAnchor.constraint(equalTo: controlsStack.centerYAnchor),
			stopButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
			stopButton.widthAnchor.constraint(equalToConstant: 44),
			stopButton.heightAnchor.constraint(equalToConstant: 44),

			controlsStack.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 12),
			controlsStack.centerXAnchor.constraint(equalTo: centerXAnchor),
			// Pin to the safe-area bottom so controls sit above the home indicator
			// even though the bar's background extends to the absolute window bottom.
			controlsStack.bottomAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.bottomAnchor, constant: -10)
		])

		[skipBackwardButton, playPauseButton, skipForwardButton].forEach { button in
			button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
			button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
		}
	}

	private func setupControlButton(_ button: UIButton, symbol: String, action: Selector, pointSize: CGFloat) {
		let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
		button.setImage(UIImage(systemName: symbol, withConfiguration: config), for: .normal)
		button.tintColor = .systemBlue
		button.addTarget(self, action: action, for: .touchUpInside)
		button.translatesAutoresizingMaskIntoConstraints = false
	}

	// MARK: - Public update API

	func update(state: SpeechSynthState, title: String?) {
		let displayTitle: String = {
			if let title, !title.isEmpty {
				return title
			}
			return NSLocalizedString("(Untitled article)", comment: "Untitled article")
		}()
		titleButton.setTitle(displayTitle, for: .normal)
		switch state {
		case .speaking(let i, let n), .paused(let i, let n):
			// Show progress at the start of the current block (fraction of blocks
			// completed). Same off-by-one fix as the Mac transport bar.
			progressView.progress = n > 0 ? Float(i) / Float(n) : 0
		case .preparing:
			break
		case .finished:
			progressView.progress = 1
		case .idle, .failed:
			progressView.progress = 0
		}
		switch state {
		case .speaking:
			let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
			playPauseButton.setImage(UIImage(systemName: "pause.fill", withConfiguration: config), for: .normal)
		default:
			let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
			playPauseButton.setImage(UIImage(systemName: "play.fill", withConfiguration: config), for: .normal)
		}
	}

	// MARK: - Actions

	@objc private func titleTapped(_ sender: Any?) { delegate?.speechTransportViewDidTapTitle(self) }
	@objc private func stopTapped(_ sender: Any?) { SpeechCoordinator.shared.stop() }
	@objc private func skipBackwardTapped(_ sender: Any?) { SpeechCoordinator.shared.skipBackward() }
	@objc private func skipForwardTapped(_ sender: Any?) { SpeechCoordinator.shared.skipForward() }
	@objc private func playPauseTapped(_ sender: Any?) { SpeechCoordinator.shared.togglePlayPause() }
}
