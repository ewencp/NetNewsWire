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

	private let topSeparator: NSBox = {
		let box = NSBox()
		box.boxType = .separator
		box.translatesAutoresizingMaskIntoConstraints = false
		return box
	}()

	private let titleButton: NSButton = {
		let button = NSButton()
		button.bezelStyle = .accessoryBarAction
		button.isBordered = false
		button.alignment = .center
		button.lineBreakMode = .byTruncatingTail
		button.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
		button.contentTintColor = .labelColor
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

	override var isOpaque: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		NSColor.windowBackgroundColor.set()
		dirtyRect.intersection(bounds).fill()
	}

	private func commonInit() {
		titleButton.target = self
		titleButton.action = #selector(titleTapped(_:))
		addSubview(topSeparator)
		addSubview(titleButton)
		addSubview(progressBar)

		setupControlButton(stopButton, symbol: "xmark", action: #selector(stopTapped(_:)))
		setupControlButton(skipBackwardButton, symbol: "backward.fill", action: #selector(skipBackwardTapped(_:)))
		setupControlButton(playPauseButton, symbol: "play.fill", action: #selector(playPauseTapped(_:)))
		setupControlButton(skipForwardButton, symbol: "forward.fill", action: #selector(skipForwardTapped(_:)))

		// Make play/pause slightly larger.
		playPauseButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
		stopButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
		skipBackwardButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
		skipForwardButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)

		let controlsStack = NSStackView(views: [skipBackwardButton, playPauseButton, skipForwardButton])
		controlsStack.orientation = .horizontal
		controlsStack.spacing = 24
		controlsStack.alignment = .centerY
		controlsStack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(controlsStack)
		addSubview(stopButton)
		stopButton.translatesAutoresizingMaskIntoConstraints = false

		NSLayoutConstraint.activate([
			topSeparator.topAnchor.constraint(equalTo: topAnchor),
			topSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
			topSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
			topSeparator.heightAnchor.constraint(equalToConstant: 1),

			titleButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
			titleButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
			titleButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
			titleButton.heightAnchor.constraint(equalToConstant: 22),

			progressBar.topAnchor.constraint(equalTo: titleButton.bottomAnchor, constant: 8),
			progressBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
			progressBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
			progressBar.heightAnchor.constraint(equalToConstant: 6),

			stopButton.centerYAnchor.constraint(equalTo: controlsStack.centerYAnchor),
			stopButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
			stopButton.widthAnchor.constraint(equalToConstant: 28),
			stopButton.heightAnchor.constraint(equalToConstant: 28),

			controlsStack.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 12),
			controlsStack.centerXAnchor.constraint(equalTo: centerXAnchor),
			controlsStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10)
		])

		[stopButton, skipBackwardButton, playPauseButton, skipForwardButton].forEach { button in
			button.widthAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
			button.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
		}
	}

	private func setupControlButton(_ button: NSButton, symbol: String, action: Selector) {
		button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
		button.bezelStyle = .accessoryBarAction
		button.isBordered = false
		button.contentTintColor = .controlAccentColor
		button.target = self
		button.action = action
		button.translatesAutoresizingMaskIntoConstraints = false
	}

	// MARK: - Public update API

	func update(state: SpeechSynthState, title: String?) {
		let displayTitle = title?.isEmpty == false ? title : NSLocalizedString("(Untitled article)", comment: "Untitled article")
		titleButton.title = displayTitle ?? ""
		switch state {
		case .speaking(let i, let n), .paused(let i, let n):
			// Show progress at the *start* of the current block. Without a
			// sub-block fraction, mid-block position would otherwise show
			// "completed" before any audio of the block has been spoken.
			// Future: smooth progress within a block via willSpeakWord (see TODO).
			progressBar.doubleValue = n > 0 ? Double(i) / Double(n) : 0
		case .preparing:
			// Leave progress untouched during skip/replace transitions to avoid
			// a visible flicker to zero between didCancel and didStart.
			break
		case .finished:
			progressBar.doubleValue = 1
		case .idle, .failed:
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
