//
//  SpeechTransportBar.swift
//  NetNewsWire
//

import AppKit
import ArticleSpeech
import SpeechCoordinatorKit

@MainActor
protocol SpeechTransportBarDelegate: AnyObject {
	func speechTransportBarDidTapTitle(_ bar: SpeechTransportBar)
}

final class SpeechTransportBar: NSView {

	weak var delegate: SpeechTransportBarDelegate?

	private let titleButton: NSButton = {
		let button = NSButton()
		button.isBordered = false
		button.alignment = .left
		button.lineBreakMode = .byTruncatingTail
		button.translatesAutoresizingMaskIntoConstraints = false
		return button
	}()

	private let progressBar: NSProgressIndicator = {
		let bar = NSProgressIndicator()
		bar.style = .bar
		bar.isIndeterminate = false
		bar.minValue = 0
		bar.maxValue = 1
		bar.translatesAutoresizingMaskIntoConstraints = false
		return bar
	}()

	private let stopButton = NSButton()
	private let skipBackwardButton = NSButton()
	private let playPauseButton = NSButton()
	private let skipForwardButton = NSButton()

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
		layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

		titleButton.target = self
		titleButton.action = #selector(titleTapped(_:))
		addSubview(titleButton)

		addSubview(progressBar)

		setupControlButton(stopButton, symbol: "xmark", action: #selector(stopTapped(_:)))
		setupControlButton(skipBackwardButton, symbol: "backward.fill", action: #selector(skipBackwardTapped(_:)))
		setupControlButton(playPauseButton, symbol: "play.fill", action: #selector(playPauseTapped(_:)))
		setupControlButton(skipForwardButton, symbol: "forward.fill", action: #selector(skipForwardTapped(_:)))

		let controlsStack = NSStackView(views: [skipBackwardButton, playPauseButton, skipForwardButton])
		controlsStack.orientation = .horizontal
		controlsStack.spacing = 16
		controlsStack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(controlsStack)
		addSubview(stopButton)
		stopButton.translatesAutoresizingMaskIntoConstraints = false

		NSLayoutConstraint.activate([
			titleButton.topAnchor.constraint(equalTo: topAnchor, constant: 6),
			titleButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
			titleButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
			titleButton.heightAnchor.constraint(equalToConstant: 22),

			progressBar.topAnchor.constraint(equalTo: titleButton.bottomAnchor, constant: 6),
			progressBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
			progressBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
			progressBar.heightAnchor.constraint(equalToConstant: 4),

			stopButton.centerYAnchor.constraint(equalTo: controlsStack.centerYAnchor),
			stopButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),

			controlsStack.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 8),
			controlsStack.centerXAnchor.constraint(equalTo: centerXAnchor),
			controlsStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
		])
	}

	private func setupControlButton(_ button: NSButton, symbol: String, action: Selector) {
		button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
		button.bezelStyle = .recessed
		button.isBordered = false
		button.target = self
		button.action = action
		button.translatesAutoresizingMaskIntoConstraints = false
	}

	// MARK: - Public update API

	func update(state: SpeechSynthState, title: String?) {
		titleButton.title = title ?? ""
		switch state {
		case .speaking(let i, let n), .paused(let i, let n):
			progressBar.doubleValue = n > 0 ? Double(i + 1) / Double(n) : 0
		default:
			progressBar.doubleValue = 0
		}
		switch state {
		case .speaking:
			playPauseButton.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: nil)
		default:
			playPauseButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)
		}
	}

	// MARK: - Actions

	@objc private func titleTapped(_ sender: Any?) {
		delegate?.speechTransportBarDidTapTitle(self)
	}

	@objc private func stopTapped(_ sender: Any?) {
		SpeechCoordinator.shared.stop()
	}

	@objc private func skipBackwardTapped(_ sender: Any?) {
		SpeechCoordinator.shared.skipBackward()
	}

	@objc private func skipForwardTapped(_ sender: Any?) {
		SpeechCoordinator.shared.skipForward()
	}

	@objc private func playPauseTapped(_ sender: Any?) {
		SpeechCoordinator.shared.togglePlayPause()
	}
}
