//
//  SpeechTransportPresenter.swift
//  NetNewsWire-iOS
//

import UIKit
import ArticleSpeech
import SpeechCoordinatorKit

/// Hosts the transport bar inside a host view, anchored to the host's safe-area
/// bottom. When hosted inside `ArticleViewController.view` the safe area
/// excludes the navigation controller's toolbar, so the bar sits above the
/// toolbar without overlapping.
@MainActor
final class SpeechTransportPresenter {

	static let shared = SpeechTransportPresenter()

	private let transportView = SpeechTransportView()
	private weak var hostView: UIView?
	private var heightConstraint: NSLayoutConstraint?

	private init() {
		SpeechCoordinator.shared.addObserver(self)
	}

	/// Installs the transport view as a subview of the given host view,
	/// anchored to its safe-area bottom. Called by the active VC
	/// (ArticleViewController) in viewDidAppear.
	func host(in view: UIView?) {
		guard let view, hostView !== view else { return }
		transportView.removeFromSuperview()
		hostView = view

		view.addSubview(transportView)
		transportView.translatesAutoresizingMaskIntoConstraints = false
		transportView.clipsToBounds = true
		let height = transportView.heightAnchor.constraint(equalToConstant: 0)
		heightConstraint = height
		NSLayoutConstraint.activate([
			transportView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			transportView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			transportView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
			height
		])
		applyHeight()
	}

	private func applyHeight() {
		let active = SpeechCoordinator.shared.state.isActive
		heightConstraint?.constant = active ? 120 : 0
		hostView?.bringSubviewToFront(transportView)
	}
}

extension SpeechTransportPresenter: SpeechCoordinatorObserver {

	func speechCoordinatorDidUpdate(_ coordinator: SpeechCoordinator) {
		transportView.update(state: coordinator.state, title: coordinator.playingArticleTitle)
		applyHeight()
		UIView.animate(withDuration: 0.2) { [weak self] in
			self?.hostView?.layoutIfNeeded()
		}
	}
}
