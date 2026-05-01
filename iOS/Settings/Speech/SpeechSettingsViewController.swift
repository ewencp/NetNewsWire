//
//  SpeechSettingsViewController.swift
//  NetNewsWire-iOS
//

import UIKit
import ArticleSpeech
import AppleSpeechKit
import SpeechCoordinatorKit

final class SpeechSettingsViewController: UITableViewController {

	private enum Section: Int, CaseIterable {
		case rate
		case installedVoices
		case downloadMore
		case downloadInfo
	}

	private static let rateSteps: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

	private var installedVoices: [SpeechVoice] = []
	private var recommendedVoices: [SpeechVoice] = []
	private var rateMultiplier: Float = SpeechDefaults.defaultRateMultiplier

	init() {
		super.init(style: .insetGrouped)
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		title = NSLocalizedString("Speech", comment: "Speech settings title")
		let stored = UserDefaults.standard.float(forKey: SpeechDefaults.rateMultiplierKey)
		rateMultiplier = stored == 0 ? SpeechDefaults.defaultRateMultiplier : stored
		reloadVoices()
		tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		SpeechSamplePlayer.shared.stop()
	}

	private func reloadVoices() {
		let tag = AppleSpeechVoiceCatalog.primaryLanguageTag
		installedVoices = AppleSpeechVoiceCatalog.installedVoices(matching: tag)
		let installedIDs = Set(installedVoices.map(\.identifier))
		recommendedVoices = AppleSpeechVoiceCatalog.recommendedVoices(matching: tag)
			.filter { !installedIDs.contains($0.identifier) }
		tableView.reloadData()
	}

	private func snappedRate(for value: Float) -> Float {
		Self.rateSteps.min(by: { abs($0 - value) < abs($1 - value) }) ?? value
	}

	override func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		switch Section(rawValue: section)! {
		case .rate:             return 1
		case .installedVoices:  return installedVoices.count
		case .downloadMore:     return recommendedVoices.count
		case .downloadInfo:     return 1
		}
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		switch Section(rawValue: section)! {
		case .rate:             return NSLocalizedString("Speaking Rate", comment: "")
		case .installedVoices:  return NSLocalizedString("Installed Voices", comment: "")
		case .downloadMore:     return recommendedVoices.isEmpty ? nil : NSLocalizedString("Download More", comment: "")
		case .downloadInfo:     return nil
		}
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
		cell.contentView.subviews.forEach { $0.removeFromSuperview() }
		switch Section(rawValue: indexPath.section)! {
		case .rate:
			configureRateCell(cell)
		case .installedVoices:
			let voice = installedVoices[indexPath.row]
			cell.textLabel?.text = displayString(for: voice)
			let storedID = UserDefaults.standard.string(forKey: SpeechDefaults.voiceIdentifierKey)
			cell.accessoryType = (voice.identifier == storedID) ? .checkmark : .none
		case .downloadMore:
			let voice = recommendedVoices[indexPath.row]
			cell.textLabel?.text = displayString(for: voice)
			cell.textLabel?.textColor = .secondaryLabel
			cell.accessoryType = .disclosureIndicator
		case .downloadInfo:
			cell.textLabel?.text = SpeechDownloadInstructions.title
			cell.textLabel?.textColor = .systemBlue
		}
		return cell
	}

	private func configureRateCell(_ cell: UITableViewCell) {
		let slider = UISlider()
		slider.minimumValue = 0.5
		slider.maximumValue = 3.0
		slider.value = rateMultiplier
		slider.addTarget(self, action: #selector(rateChanged(_:)), for: .valueChanged)
		slider.translatesAutoresizingMaskIntoConstraints = false

		let valueLabel = UILabel()
		valueLabel.text = String(format: "%.2g×", rateMultiplier)
		valueLabel.font = .preferredFont(forTextStyle: .footnote)
		valueLabel.textColor = .secondaryLabel
		valueLabel.translatesAutoresizingMaskIntoConstraints = false
		valueLabel.tag = 1001
		valueLabel.setContentHuggingPriority(.required, for: .horizontal)

		let sampleButton = UIButton(type: .system)
		sampleButton.setTitle(NSLocalizedString("Sample", comment: "Sample voice button"), for: .normal)
		sampleButton.addTarget(self, action: #selector(samplePlay(_:)), for: .touchUpInside)
		sampleButton.translatesAutoresizingMaskIntoConstraints = false
		sampleButton.setContentHuggingPriority(.required, for: .horizontal)

		let stack = UIStackView(arrangedSubviews: [slider, valueLabel, sampleButton])
		stack.axis = .horizontal
		stack.spacing = 12
		stack.alignment = .center
		stack.translatesAutoresizingMaskIntoConstraints = false
		cell.contentView.addSubview(stack)
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
			stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 8),
			stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -8)
		])
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		switch Section(rawValue: indexPath.section)! {
		case .installedVoices:
			let voice = installedVoices[indexPath.row]
			let storedID = UserDefaults.standard.string(forKey: SpeechDefaults.voiceIdentifierKey)
			guard storedID != voice.identifier else {
				tableView.deselectRow(at: indexPath, animated: true)
				return
			}
			UserDefaults.standard.set(voice.identifier, forKey: SpeechDefaults.voiceIdentifierKey)
			tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
			SpeechCoordinator.shared.applyCurrentSettings()
		case .downloadMore:
			// iOS doesn't expose a public deep-link to Accessibility → Voices,
			// so the most useful action is to show the per-OS-version
			// instructions for how to navigate there manually.
			showDownloadInstructions()
		case .downloadInfo:
			showDownloadInstructions()
		case .rate:
			break
		}
		tableView.deselectRow(at: indexPath, animated: true)
	}

	@objc private func rateChanged(_ sender: UISlider) {
		let snapped = snappedRate(for: sender.value)
		sender.value = snapped
		guard rateMultiplier != snapped else { return }
		rateMultiplier = snapped
		UserDefaults.standard.set(snapped, forKey: SpeechDefaults.rateMultiplierKey)
		// Update the inline value label.
		if let label = sender.superview?.viewWithTag(1001) as? UILabel {
			label.text = String(format: "%.2g×", snapped)
		}
		SpeechCoordinator.shared.applyCurrentSettings()
	}

	@objc private func samplePlay(_ sender: Any?) {
		let voice = currentSelectedVoice() ?? AppleSpeechVoiceCatalog.systemDefault
		SpeechSamplePlayer.shared.playSample(voice: voice, rateMultiplier: rateMultiplier)
	}

	private func currentSelectedVoice() -> SpeechVoice? {
		guard let storedID = UserDefaults.standard.string(forKey: SpeechDefaults.voiceIdentifierKey) else {
			return nil
		}
		return installedVoices.first(where: { $0.identifier == storedID })
	}

	private func showDownloadInstructions() {
		let alert = UIAlertController(
			title: SpeechDownloadInstructions.title,
			message: SpeechDownloadInstructions.body,
			preferredStyle: .alert
		)
		alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
		present(alert, animated: true)
	}

	private func displayString(for voice: SpeechVoice) -> String {
		let tier: String
		switch voice.qualityTier {
		case .premium:  tier = "Premium"
		case .enhanced: tier = "Enhanced"
		case .standard: tier = "Standard"
		}
		let gender: String
		switch voice.gender {
		case .female:      gender = "Female"
		case .male:        gender = "Male"
		case .neutral:     gender = "Neutral"
		case .unspecified: gender = ""
		}
		var components = [voice.displayName]
		if !gender.isEmpty { components.append(gender) }
		components.append(tier)
		components.append(voice.language)
		return components.joined(separator: " · ")
	}
}
