//
//  HelpURL.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 9/29/25.
//  Copyright © 2025 Ranchero Software. All rights reserved.
//

import Foundation

enum HelpURL: String {

	case helpHome = "https://github.com/ewencp/NetNewsWire#readme"
	case website = "https://github.com/ewencp/NetNewsWire"
	case releaseNotes = "https://github.com/ewencp/NetNewsWire/releases/"
	case howToSupportNetNewsWire = "https://github.com/Ranchero-Software/NetNewsWire/blob/main/Technotes/HowToSupportNetNewsWire.markdown"
	case githubRepo = "https://github.com/ewencp/NetNewsWire/"
	case bugTracker = "https://github.com/ewencp/NetNewsWire/issues"
	case discourse = "https://discourse.netnewswire.com/"
	case technotes = "https://github.com/ewencp/NetNewsWire/tree/main/Technotes"
	case privacyPolicy = "https://netnewswire.com/privacypolicy.html"

#if os(macOS)
	@MainActor func open() {
		Browser.open(self.rawValue, inBackground: false)
	}
#endif
}
