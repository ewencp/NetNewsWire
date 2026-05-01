//
//  DetailContainerView.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 2/12/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import AppKit

final class DetailContainerView: NSView {

	@IBOutlet var detailStatusBarView: DetailStatusBarView!

	var contentViewConstraints: [NSLayoutConstraint]?
	private var contentBottomConstraint: NSLayoutConstraint?

	/// Bottom inset applied to the contentView. Used by the speech transport bar
	/// to keep the bottom edge of article content above the bar without overlap.
	var contentBottomInset: CGFloat = 0 {
		didSet {
			if contentBottomInset != oldValue {
				contentBottomConstraint?.constant = -contentBottomInset
			}
		}
	}

	var contentView: NSView? {
		didSet {
			if contentView == oldValue {
				return
			}

			if let currentConstraints = contentViewConstraints {
				NSLayoutConstraint.deactivate(currentConstraints)
			}
			contentViewConstraints = nil
			contentBottomConstraint = nil
			oldValue?.removeFromSuperviewWithoutNeedingDisplay()

			if let contentView = contentView {
				contentView.translatesAutoresizingMaskIntoConstraints = false
				addSubview(contentView, positioned: .below, relativeTo: detailStatusBarView)
				let bottom = contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -contentBottomInset)
				contentBottomConstraint = bottom
				let constraints = [
					contentView.topAnchor.constraint(equalTo: topAnchor),
					contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
					contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
					bottom
				]
				NSLayoutConstraint.activate(constraints)
				contentViewConstraints = constraints
			}
		}
	}

	override func draw(_ dirtyRect: NSRect) {
		NSColor.controlBackgroundColor.set()
		let r = dirtyRect.intersection(bounds)
		r.fill()
	}
}
