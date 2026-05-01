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
		// Add the bar as the topmost subview so it overlays the WKWebView when active.
		view.addSubview(speechTransportBar, positioned: .above, relativeTo: nil)
		let height = speechTransportBar.heightAnchor.constraint(equalToConstant: 0)
		speechTransportBarHeightConstraint = height
		NSLayoutConstraint.activate([
			speechTransportBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			speechTransportBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			speechTransportBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			height
		])
	}

	// MARK: - API

	func setState(_ state: DetailState, mode: TimelineSourceMode) {
		switch mode {
		case .regular:
			detailStateForRegular = state
		case .search:
			detailStateForSearch = state
		}
		refreshSpeechIfNeededForState(state)
	}

	private func refreshSpeechIfNeededForState(_ state: DetailState) {
		let coordinator = SpeechCoordinator.shared
		guard coordinator.state.isActive, let playingID = coordinator.playingArticleID else {
			return
		}
		let updatedSource: (Article, String)?
		switch state {
		case .article(let article, _) where article.articleID == playingID:
			updatedSource = (article, article.body ?? "")
		case .extracted(let article, let extracted, _) where article.articleID == playingID:
			updatedSource = (article, extracted.content ?? article.body ?? "")
		case .summarized(let article, let summarized, _) where article.articleID == playingID:
			updatedSource = (article, summarized.contentHTML)
		default:
			updatedSource = nil
		}
		guard let (article, sourceHTML) = updatedSource else { return }
		// Preserve the user's paused state across the content swap.
		let wasPaused: Bool
		if case .paused = coordinator.state { wasPaused = true } else { wasPaused = false }
		coordinator.startPlayback(for: article, sourceHTML: sourceHTML, keepPaused: wasPaused)
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
		let height: CGFloat = shouldShow ? 108 : 0
		speechTransportBarHeightConstraint?.constant = height
		speechTransportBar.isHidden = !shouldShow
		speechTransportBar.update(state: coordinator.state, title: coordinator.playingArticleTitle)
		// Inset the article content area so the bar doesn't overlay the last lines.
		containerView.contentBottomInset = height
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
