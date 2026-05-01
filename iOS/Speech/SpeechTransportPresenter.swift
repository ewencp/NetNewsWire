//
//  SpeechTransportPresenter.swift
//  NetNewsWire-iOS
//

import UIKit
import ArticleSpeech
import SpeechCoordinatorKit

/// Owns the window-level transport view so it persists across navigation
/// pushes/pops. Visibility is driven by `SpeechCoordinator` state changes.
@MainActor
final class SpeechTransportPresenter {

	private weak var window: UIWindow?
	private let transportView = SpeechTransportView()
	private var heightConstraint: NSLayoutConstraint?

	init(window: UIWindow) {
		self.window = window
		install()
		SpeechCoordinator.shared.addObserver(self)
	}

	private func install() {
		guard let window else { return }
		window.addSubview(transportView)
		transportView.translatesAutoresizingMaskIntoConstraints = false
		transportView.clipsToBounds = true
		let height = transportView.heightAnchor.constraint(equalToConstant: 0)
		heightConstraint = height
		NSLayoutConstraint.activate([
			transportView.leadingAnchor.constraint(equalTo: window.leadingAnchor),
			transportView.trailingAnchor.constraint(equalTo: window.trailingAnchor),
			transportView.bottomAnchor.constraint(equalTo: window.bottomAnchor),
			height
		])
	}
}

extension SpeechTransportPresenter: SpeechCoordinatorObserver {

	func speechCoordinatorDidUpdate(_ coordinator: SpeechCoordinator) {
		guard let window else { return }
		let shouldShow = coordinator.state.isActive
		// Bring to front in case something else added a subview to the window after init.
		window.bringSubviewToFront(transportView)
		// Reserve space for the home-indicator inset when shown so the bar's content
		// stays above it; otherwise collapse to zero.
		let bottomInset = window.safeAreaInsets.bottom
		heightConstraint?.constant = shouldShow ? (120 + bottomInset) : 0
		transportView.update(state: coordinator.state, title: coordinator.playingArticleTitle)
		UIView.animate(withDuration: 0.2) {
			window.layoutIfNeeded()
		}
	}
}
