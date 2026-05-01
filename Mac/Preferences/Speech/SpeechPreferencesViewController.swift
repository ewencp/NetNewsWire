//
//  SpeechPreferencesViewController.swift
//  NetNewsWire
//

import AppKit
import ArticleSpeech
import AppleSpeechKit
import SpeechCoordinatorKit

final class SpeechPreferencesViewController: NSViewController {

	private let voiceTableView = NSTableView()
	private let voiceScrollView = NSScrollView()
	private let rateSlider = NSSlider()
	private let rateLabel = NSTextField(labelWithString: "")
	private let samplePlayButton = NSButton()
	private let downloadInfoButton = NSButton()
	private let primaryLanguagePopUp = NSPopUpButton()

	private struct VoiceRow {
		let voice: SpeechVoice
		let isInstalled: Bool
	}

	private var installedVoices: [VoiceRow] = []
	private var recommendedVoices: [VoiceRow] = []
	private var currentLanguageTag: String = AppleSpeechVoiceCatalog.primaryLanguageTag
	/// Suppresses side-effects in `tableViewSelectionDidChange` while the
	/// table is being populated programmatically (NSTableView with
	/// `allowsEmptySelection = false` auto-selects row 0 on reloadData,
	/// which would otherwise overwrite the user's stored voice).
	private var isInitializingSelection = true

	override func loadView() {
		view = NSView(frame: NSRect(x: 0, y: 0, width: 512, height: 540))
		buildUI()
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		voiceTableView.dataSource = self
		voiceTableView.delegate = self
		configureRateSlider()
		configureLanguagePopUp()
		reloadVoices()
		selectStoredVoice()
		// Allow the run loop to drain any deferred AppKit selection notifications
		// fired during initial setup before re-enabling write-back.
		DispatchQueue.main.async { [weak self] in
			self?.isInitializingSelection = false
		}
		updateRateLabel()
	}

	override func viewWillDisappear() {
		super.viewWillDisappear()
		SpeechSamplePlayer.shared.stop()
	}

	// MARK: - UI construction

	private func buildUI() {
		let voiceHeader = sectionLabel("Voice")
		voiceScrollView.translatesAutoresizingMaskIntoConstraints = false
		voiceScrollView.hasVerticalScroller = true
		voiceScrollView.borderType = .bezelBorder

		voiceTableView.headerView = nil
		voiceTableView.allowsMultipleSelection = false
		voiceTableView.allowsEmptySelection = false
		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("voice"))
		column.title = ""
		column.resizingMask = .autoresizingMask
		voiceTableView.addTableColumn(column)
		voiceScrollView.documentView = voiceTableView

		let rateHeader = sectionLabel("Rate")
		rateSlider.translatesAutoresizingMaskIntoConstraints = false
		rateSlider.target = self
		rateSlider.action = #selector(rateChanged(_:))
		rateLabel.translatesAutoresizingMaskIntoConstraints = false
		rateLabel.alignment = .right
		rateLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

		samplePlayButton.title = NSLocalizedString("Sample", comment: "Sample voice button")
		samplePlayButton.bezelStyle = .rounded
		samplePlayButton.target = self
		samplePlayButton.action = #selector(samplePlay(_:))
		samplePlayButton.translatesAutoresizingMaskIntoConstraints = false

		downloadInfoButton.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
		downloadInfoButton.bezelStyle = .accessoryBar
		downloadInfoButton.isBordered = false
		downloadInfoButton.target = self
		downloadInfoButton.action = #selector(showDownloadInstructions(_:))
		downloadInfoButton.translatesAutoresizingMaskIntoConstraints = false
		downloadInfoButton.toolTip = SpeechDownloadInstructions.title

		let languageHeader = sectionLabel("Primary Language")
		primaryLanguagePopUp.translatesAutoresizingMaskIntoConstraints = false
		primaryLanguagePopUp.target = self
		primaryLanguagePopUp.action = #selector(languageChanged(_:))

		let rateRow = NSStackView(views: [rateSlider, rateLabel, samplePlayButton])
		rateRow.orientation = .horizontal
		rateRow.spacing = 12
		rateRow.alignment = .centerY
		rateRow.translatesAutoresizingMaskIntoConstraints = false
		rateRow.setHuggingPriority(.defaultLow, for: .horizontal)

		let voiceHeaderRow = NSStackView(views: [voiceHeader, NSView(), downloadInfoButton])
		voiceHeaderRow.orientation = .horizontal
		voiceHeaderRow.alignment = .centerY
		voiceHeaderRow.translatesAutoresizingMaskIntoConstraints = false

		let mainStack = NSStackView(views: [
			voiceHeaderRow,
			voiceScrollView,
			rateHeader,
			rateRow,
			languageHeader,
			primaryLanguagePopUp
		])
		mainStack.orientation = .vertical
		mainStack.alignment = .leading
		mainStack.spacing = 8
		mainStack.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(mainStack)

		NSLayoutConstraint.activate([
			mainStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
			mainStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
			mainStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
			mainStack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20),

			voiceScrollView.heightAnchor.constraint(equalToConstant: 280),
			voiceScrollView.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
			voiceHeaderRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
			rateRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
			rateSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
			primaryLanguagePopUp.widthAnchor.constraint(equalToConstant: 200)
		])
	}

	private func sectionLabel(_ text: String) -> NSTextField {
		let label = NSTextField(labelWithString: NSLocalizedString(text, comment: ""))
		label.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
		label.translatesAutoresizingMaskIntoConstraints = false
		return label
	}

	// MARK: - Configuration

	private static let rateSteps: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

	private func configureRateSlider() {
		rateSlider.minValue = 0.5
		rateSlider.maxValue = 3.0
		// Tick marks are visual hints only — the in-handler snap below enforces
		// the actual discrete steps, since they're not evenly spaced (0.25 apart
		// up to 2.0, then 0.5 apart through 3.0) and AppKit's `allowsTickMarkValuesOnly`
		// would force evenly-spaced positions.
		rateSlider.numberOfTickMarks = Self.rateSteps.count
		rateSlider.allowsTickMarkValuesOnly = false
		let stored = UserDefaults.standard.float(forKey: SpeechDefaults.rateMultiplierKey)
		rateSlider.floatValue = stored == 0 ? SpeechDefaults.defaultRateMultiplier : stored
	}

	private func snappedRate(for value: Float) -> Float {
		Self.rateSteps.min(by: { abs($0 - value) < abs($1 - value) }) ?? value
	}

	private func configureLanguagePopUp() {
		// Build language menu from available voices' locales (deduped).
		let languages = Set(AVAvailableLanguageTags()).sorted()
		primaryLanguagePopUp.removeAllItems()
		for tag in languages {
			let item = NSMenuItem(title: displayName(for: tag), action: nil, keyEquivalent: "")
			item.representedObject = tag
			primaryLanguagePopUp.menu?.addItem(item)
		}
		// Select the current tag.
		if let index = primaryLanguagePopUp.itemArray.firstIndex(where: { ($0.representedObject as? String) == currentLanguageTag }) {
			primaryLanguagePopUp.selectItem(at: index)
		}
	}

	private func AVAvailableLanguageTags() -> [String] {
		// Use a coarse "language code only" set (en, fr, de, ...) sourced from
		// the recommended catalog plus whatever's installed.
		let installed = AppleSpeechVoiceCatalog.installedVoices(matching: "")
		let allLanguageTags = Set(installed.map { $0.language.split(separator: "-").first.map(String.init) ?? $0.language })
		return Array(allLanguageTags)
	}

	private func displayName(for languageTag: String) -> String {
		Locale.current.localizedString(forIdentifier: languageTag) ?? languageTag
	}

	private func reloadVoices() {
		let installed = AppleSpeechVoiceCatalog.installedVoices(matching: currentLanguageTag)
		let recommended = AppleSpeechVoiceCatalog.recommendedVoices(matching: currentLanguageTag)
			.filter { !installed.map(\.identifier).contains($0.identifier) }

		installedVoices = installed.map { VoiceRow(voice: $0, isInstalled: true) }
		recommendedVoices = recommended.map { VoiceRow(voice: $0, isInstalled: false) }
		voiceTableView.reloadData()
	}

	private func selectStoredVoice() {
		guard let storedID = UserDefaults.standard.string(forKey: SpeechDefaults.voiceIdentifierKey) else {
			return
		}
		if let row = installedVoices.firstIndex(where: { $0.voice.identifier == storedID }) {
			voiceTableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
			voiceTableView.scrollRowToVisible(row)
		}
	}

	private func selectedVoice() -> SpeechVoice? {
		let row = voiceTableView.selectedRow
		guard row >= 0 else { return nil }
		if row < installedVoices.count {
			return installedVoices[row].voice
		}
		let recIndex = row - installedVoices.count - 1   // -1 for the section header pseudo-row
		guard recIndex >= 0, recIndex < recommendedVoices.count else { return nil }
		return recommendedVoices[recIndex].voice
	}

	private func updateRateLabel() {
		rateLabel.stringValue = String(format: "%.2g×", rateSlider.floatValue)
	}

	// MARK: - Actions

	@objc private func rateChanged(_ sender: NSSlider) {
		let snapped = snappedRate(for: sender.floatValue)
		sender.floatValue = snapped
		UserDefaults.standard.set(snapped, forKey: SpeechDefaults.rateMultiplierKey)
		updateRateLabel()
		SpeechCoordinator.shared.applyCurrentSettings()
	}

	@objc private func samplePlay(_ sender: Any?) {
		let voice = selectedVoice() ?? AppleSpeechVoiceCatalog.systemDefault
		SpeechSamplePlayer.shared.playSample(voice: voice, rateMultiplier: rateSlider.floatValue)
	}

	@objc private func showDownloadInstructions(_ sender: Any?) {
		let alert = NSAlert()
		alert.messageText = SpeechDownloadInstructions.title
		alert.informativeText = SpeechDownloadInstructions.body
		alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
		alert.runModal()
	}

	@objc private func languageChanged(_ sender: NSPopUpButton) {
		guard let tag = sender.selectedItem?.representedObject as? String else { return }
		currentLanguageTag = tag
		UserDefaults.standard.set(tag, forKey: SpeechDefaults.primaryLanguageKey)
		reloadVoices()
	}
}

extension SpeechPreferencesViewController: NSTableViewDataSource, NSTableViewDelegate {

	// Layout: [installed rows] [section header pseudo-row] [recommended rows]
	// The header is non-selectable; selection persists only for installed voices.

	func numberOfRows(in tableView: NSTableView) -> Int {
		if recommendedVoices.isEmpty {
			return installedVoices.count
		}
		return installedVoices.count + 1 + recommendedVoices.count
	}

	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		if row < installedVoices.count {
			return cellView(for: installedVoices[row], dimmed: false)
		}
		if row == installedVoices.count, !recommendedVoices.isEmpty {
			return headerCellView(text: NSLocalizedString("Available to download (open System Settings)", comment: ""))
		}
		let recIndex = row - installedVoices.count - 1
		return cellView(for: recommendedVoices[recIndex], dimmed: true)
	}

	func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
		if row < installedVoices.count {
			return true
		}
		// Header row and recommended (uninstalled) rows are not selectable for playback.
		return false
	}

	func tableViewSelectionDidChange(_ notification: Notification) {
		guard !isInitializingSelection else { return }
		guard let voice = selectedVoice(), voice.isInstalled else { return }
		// No-op if the new selection matches what's already stored.
		let storedID = UserDefaults.standard.string(forKey: SpeechDefaults.voiceIdentifierKey)
		guard storedID != voice.identifier else { return }
		UserDefaults.standard.set(voice.identifier, forKey: SpeechDefaults.voiceIdentifierKey)
		SpeechCoordinator.shared.applyCurrentSettings()
	}

	private func cellView(for row: VoiceRow, dimmed: Bool) -> NSView {
		let v = NSTableCellView()
		let label = NSTextField(labelWithString: voiceDisplayString(for: row.voice))
		label.translatesAutoresizingMaskIntoConstraints = false
		label.lineBreakMode = .byTruncatingTail
		if dimmed {
			label.textColor = .secondaryLabelColor
		}
		v.addSubview(label)
		NSLayoutConstraint.activate([
			label.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 6),
			label.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -6),
			label.centerYAnchor.constraint(equalTo: v.centerYAnchor)
		])
		return v
	}

	private func headerCellView(text: String) -> NSView {
		let v = NSTableCellView()
		let label = NSTextField(labelWithString: text)
		label.translatesAutoresizingMaskIntoConstraints = false
		label.font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
		label.textColor = .secondaryLabelColor
		v.addSubview(label)
		NSLayoutConstraint.activate([
			label.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 6),
			label.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -6),
			label.centerYAnchor.constraint(equalTo: v.centerYAnchor)
		])
		return v
	}

	private func voiceDisplayString(for voice: SpeechVoice) -> String {
		let tier: String
		switch voice.qualityTier {
		case .premium:  tier = "Premium"
		case .enhanced: tier = "Enhanced"
		case .standard: tier = "Standard"
		}
		let gender: String
		switch voice.gender {
		case .female:       gender = "Female"
		case .male:         gender = "Male"
		case .neutral:      gender = "Neutral"
		case .unspecified:  gender = ""
		}
		var components: [String] = [voice.displayName]
		if !gender.isEmpty {
			components.append(gender)
		}
		components.append(tier)
		components.append(voice.language)
		return components.joined(separator: " · ")
	}
}
