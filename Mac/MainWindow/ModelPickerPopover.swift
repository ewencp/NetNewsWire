//
//  ModelPickerPopover.swift
//  NetNewsWire
//

import AppKit
import OllamaKit

final class ModelPickerPopover: NSPopover, NSTableViewDataSource, NSTableViewDelegate {

	var onModelSelected: ((String) -> Void)?

	private let dataSource = ModelPickerDataSource()
	private let tableView = NSTableView()
	private let scrollView = NSScrollView()
	private let statusLabel = NSTextField(wrappingLabelWithString: "Loading models...")
	private let progressIndicator = NSProgressIndicator()
	private var downloadTask: Task<Void, Never>?
	private var currentModelName: String?

	override init() {
		super.init()
		contentSize = NSSize(width: 320, height: 220)
		behavior = .transient
		setupUI()
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) not implemented")
	}

	func load(currentModel: String? = nil) {
		currentModelName = currentModel
		statusLabel.stringValue = "Loading models..."
		statusLabel.isHidden = false
		progressIndicator.isHidden = true
		scrollView.isHidden = true

		Task { @MainActor in
			await dataSource.loadModels()
			updateUI()
		}
	}

	// MARK: - Private

	private func setupUI() {
		let viewController = NSViewController()
		let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 220))

		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("model"))
		column.width = 300
		tableView.addTableColumn(column)
		tableView.delegate = self
		tableView.dataSource = self
		tableView.headerView = nil
		tableView.doubleAction = #selector(rowDoubleClicked)
		tableView.target = self
		tableView.rowHeight = 28

		scrollView.documentView = tableView
		scrollView.hasVerticalScroller = true
		scrollView.translatesAutoresizingMaskIntoConstraints = false

		statusLabel.translatesAutoresizingMaskIntoConstraints = false
		statusLabel.alignment = .center
		statusLabel.font = .systemFont(ofSize: 13)

		progressIndicator.translatesAutoresizingMaskIntoConstraints = false
		progressIndicator.style = .bar
		progressIndicator.minValue = 0
		progressIndicator.maxValue = 1
		progressIndicator.isIndeterminate = false
		progressIndicator.isHidden = true

		containerView.addSubview(scrollView)
		containerView.addSubview(statusLabel)
		containerView.addSubview(progressIndicator)

		NSLayoutConstraint.activate([
			scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
			scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
			scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

			statusLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
			statusLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor, constant: -12),
			statusLabel.widthAnchor.constraint(lessThanOrEqualTo: containerView.widthAnchor, constant: -40),

			progressIndicator.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 40),
			progressIndicator.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -40),
			progressIndicator.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
		])

		viewController.view = containerView
		contentViewController = viewController
	}

	private func updateUI() {
		if let error = dataSource.errorMessage {
			statusLabel.stringValue = error
			statusLabel.isHidden = false
			progressIndicator.isHidden = true
			scrollView.isHidden = true
		} else if dataSource.items.isEmpty {
			statusLabel.stringValue = "No models available."
			statusLabel.isHidden = false
			progressIndicator.isHidden = true
			scrollView.isHidden = true
		} else {
			statusLabel.isHidden = true
			progressIndicator.isHidden = true
			scrollView.isHidden = false
			tableView.reloadData()
		}
	}

	@objc private func rowDoubleClicked() {
		let row = tableView.clickedRow
		guard row >= 0, row < dataSource.items.count else {
			return
		}

		let item = dataSource.items[row]

		if item.isLocal {
			onModelSelected?(item.name)
			close()
		} else {
			startDownload(modelName: item.name)
		}
	}

	private func startDownload(modelName: String) {
		// Prevent popover from closing during download
		behavior = .applicationDefined

		statusLabel.stringValue = "Downloading \(modelName)..."
		statusLabel.isHidden = false
		progressIndicator.doubleValue = 0
		progressIndicator.isHidden = false
		scrollView.isHidden = true

		let service = OllamaService()
		downloadTask = Task { @MainActor in
			do {
				try await service.pullModel(modelName) { [weak self] progress in
					Task { @MainActor in
						self?.progressIndicator.doubleValue = progress
					}
				}
				onModelSelected?(modelName)
				close()
			} catch {
				statusLabel.stringValue = "Download failed: \(error.localizedDescription)"
				progressIndicator.isHidden = true
				behavior = .transient
			}
		}
	}

	// MARK: - NSTableViewDataSource

	func numberOfRows(in tableView: NSTableView) -> Int {
		dataSource.items.count
	}

	// MARK: - NSTableViewDelegate

	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let item = dataSource.items[row]
		let isSelected = item.isLocal && item.name == currentModelName

		let cell = NSTableCellView()

		let checkmark = NSTextField(labelWithString: isSelected ? "✓" : "")
		checkmark.translatesAutoresizingMaskIntoConstraints = false
		checkmark.font = .systemFont(ofSize: 13, weight: .bold)
		checkmark.textColor = .controlAccentColor

		let textField = NSTextField(labelWithString: "")
		textField.translatesAutoresizingMaskIntoConstraints = false

		if item.isLocal {
			textField.stringValue = "\(item.displayName)  (\(item.sizeDescription))"
			textField.textColor = .labelColor
			if isSelected {
				textField.font = .systemFont(ofSize: 13, weight: .medium)
			}
		} else {
			textField.stringValue = "\(item.displayName)  (\(item.sizeDescription))"
			textField.textColor = .secondaryLabelColor
		}

		cell.addSubview(checkmark)
		cell.addSubview(textField)
		NSLayoutConstraint.activate([
			checkmark.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
			checkmark.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
			checkmark.widthAnchor.constraint(equalToConstant: 16),
			textField.leadingAnchor.constraint(equalTo: checkmark.trailingAnchor, constant: 4),
			textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
			textField.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
		])

		return cell
	}
}
