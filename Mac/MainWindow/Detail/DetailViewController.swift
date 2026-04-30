//
//  DetailViewController.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 7/26/15.
//  Copyright © 2015 Ranchero Software, LLC. All rights reserved.
//

import Foundation
import WebKit
import RSCore
import Articles
import RSWeb
import ArticleAI
import ArticleSpeech
import SpeechCoordinatorKit

enum DetailState: Equatable {
	case noSelection
	case multipleSelection
	case loading
	case article(Article, CGFloat?)
	case extracted(Article, ExtractedArticle, CGFloat?)
	case summarized(Article, SummarizedArticle, CGFloat?)
}

final class DetailViewController: NSViewController, WKUIDelegate {

	@IBOutlet var containerView: DetailContainerView!
	@IBOutlet var statusBarView: DetailStatusBarView!

	private lazy var regularWebViewController = createWebViewController()
	private var searchWebViewController: DetailWebViewController?

	var windowState: DetailWindowState {
		currentWebViewController.windowState
	}

	var currentDetailState: DetailState {
		switch currentSourceMode {
		case .regular: return detailStateForRegular
		case .search:  return detailStateForSearch
		}
	}

	private var currentWebViewController: DetailWebViewController! {
		didSet {
			let webview = currentWebViewController.view
			if containerView.contentView === webview {
				return
			}
			statusBarView.mouseoverLink = nil
			containerView.contentView = webview
		}
	}

	private var currentSourceMode: TimelineSourceMode = .regular {
		didSet {
			currentWebViewController = webViewController(for: currentSourceMode)
		}
	}

	private var detailStateForRegular: DetailState = .noSelection {
		didSet {
			webViewController(for: .regular).state = detailStateForRegular
		}
	}

	private var detailStateForSearch: DetailState = .noSelection {
		didSet {
			webViewController(for: .search).state = detailStateForSearch
		}
	}

	private var isArticleContentJavascriptEnabled = AppDefaults.shared.isArticleContentJavascriptEnabled

	private lazy var speechTransportBar: SpeechTransportBar = {
		let bar = SpeechTransportBar()
		bar.translatesAutoresizingMaskIntoConstraints = false
		bar.isHidden = true
		return bar
	}()

	private var speechTransportBarHeightConstraint: NSLayoutConstraint?

	override func viewDidLoad() {
		currentWebViewController = regularWebViewController
		NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
			Task { @MainActor in
				self?.userDefaultsDidChange()
			}
		}
		installSpeechTransportBar()
		SpeechCoordinator.shared.addObserver(self)
	}

	private func installSpeechTransportBar() {
		view.addSubview(speechTransportBar)
		let height = speechTransportBar.heightAnchor.constraint(equalToConstant: 0)
		speechTransportBarHeightConstraint = height
		NSLayoutConstraint.activate([
			speechTransportBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			speechTransportBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			speechTransportBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			height
		])
		// Storyboard pins containerView to the bottom of view; replace that constraint
		// so the container's bottom follows the transport bar's top instead.
		for constraint in view.constraints {
			let firstIsContainer = (constraint.firstItem as? NSView) === containerView
			let secondIsContainer = (constraint.secondItem as? NSView) === containerView
			let firstIsView = (constraint.firstItem as? NSView) === view
			let secondIsView = (constraint.secondItem as? NSView) === view
			let touchesBottom = constraint.firstAttribute == .bottom || constraint.secondAttribute == .bottom
			if touchesBottom && ((firstIsContainer && secondIsView) || (secondIsContainer && firstIsView)) {
				constraint.isActive = false
			}
		}
		containerView.bottomAnchor.constraint(equalTo: speechTransportBar.topAnchor).isActive = true
	}

	// MARK: - API

	func setState(_ state: DetailState, mode: TimelineSourceMode) {
		switch mode {
		case .regular:
			detailStateForRegular = state
		case .search:
			detailStateForSearch = state
		}
	}

	func showDetail(for mode: TimelineSourceMode) {
		currentSourceMode = mode
	}

	func stopMediaPlayback() {
		currentWebViewController.stopMediaPlayback()
	}

	func canScrollDown() async -> Bool {
		await currentWebViewController.canScrollDown()
	}

	func canScrollUp() async -> Bool {
		await currentWebViewController.canScrollUp()
	}

	override func scrollPageDown(_ sender: Any?) {
		currentWebViewController.scrollPageDown(sender)
	}

	override func scrollPageUp(_ sender: Any?) {
		currentWebViewController.scrollPageUp(sender)
	}

	// MARK: - Navigation

	func focus() {
		guard let window = currentWebViewController.webView.window else {
			return
		}
		window.makeFirstResponderUnlessDescendantIsFirstResponder(currentWebViewController.webView)
	}
}

// MARK: - DetailWebViewControllerDelegate

extension DetailViewController: DetailWebViewControllerDelegate {

	func mouseDidEnter(_ detailWebViewController: DetailWebViewController, link: String) {
		guard !link.isEmpty, detailWebViewController === currentWebViewController else {
			return
		}
		statusBarView.mouseoverLink = link
	}

	func mouseDidExit(_ detailWebViewController: DetailWebViewController) {
		guard detailWebViewController === currentWebViewController else {
			return
		}
		statusBarView.mouseoverLink = nil
	}
}

// MARK: - Private

private extension DetailViewController {

	func createWebViewController() -> DetailWebViewController {
		let controller = DetailWebViewController()
		controller.delegate = self
		controller.state = .noSelection
		return controller
	}

	func webViewController(for mode: TimelineSourceMode) -> DetailWebViewController {
		switch mode {
		case .regular:
			return regularWebViewController
		case .search:
			if searchWebViewController == nil {
				searchWebViewController = createWebViewController()
			}
			return searchWebViewController!
		}
	}

	func userDefaultsDidChange() {
		if AppDefaults.shared.isArticleContentJavascriptEnabled != isArticleContentJavascriptEnabled {
			isArticleContentJavascriptEnabled = AppDefaults.shared.isArticleContentJavascriptEnabled
			createNewWebViewsAndRestoreState()
		}
	}

	func createNewWebViewsAndRestoreState() {

		regularWebViewController = createWebViewController()
		currentWebViewController = regularWebViewController
		regularWebViewController.state = detailStateForRegular

		searchWebViewController = nil

		if currentSourceMode == .search {
			searchWebViewController = createWebViewController()
			currentWebViewController = searchWebViewController
			searchWebViewController!.state = detailStateForSearch
		}
	}
}

// MARK: - SpeechCoordinatorObserver

extension DetailViewController: SpeechCoordinatorObserver {

	public func speechCoordinatorDidUpdate(_ coordinator: SpeechCoordinator) {
		updateSpeechTransportBar()
	}

	private func updateSpeechTransportBar() {
		let coordinator = SpeechCoordinator.shared
		let shouldShow = coordinator.state.isActive
		speechTransportBarHeightConstraint?.constant = shouldShow ? 108 : 0
		speechTransportBar.isHidden = !shouldShow
		speechTransportBar.update(state: coordinator.state, title: coordinator.playingArticleTitle)
		NSAnimationContext.runAnimationGroup { context in
			context.duration = 0.2
			view.layoutSubtreeIfNeeded()
		}
	}
}

extension DetailViewController: SpeechTransportBarDelegate {
	func speechTransportBarDidTapTitle(_ bar: SpeechTransportBar) {
		// Future: navigate timeline to the playing article.
	}
}
