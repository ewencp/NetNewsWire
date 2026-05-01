import Foundation

/// Instructions for downloading additional `AVSpeechSynthesisVoice` voices.
/// Apple has shifted the path across OS releases; rather than detect the OS
/// version and pick one path, we list all known paths so the user can find
/// whichever matches their OS.
public enum SpeechDownloadInstructions {

	public static let title = NSLocalizedString(
		"How to download voices",
		comment: "Title of the panel that explains where in System Settings to download additional speech voices."
	)

	public static let body: String = """
	iOS / iPadOS 26 (Tahoe) and later:
	  Settings → Accessibility → Read and Speak → Voices → [language] → tap a voice and select Download.

	iOS / iPadOS 17–18:
	  Settings → Accessibility → Spoken Content → Voices → [language] → tap a voice and select Download.

	macOS 26 (Tahoe) and later:
	  System Settings → Accessibility → Read and Speak → System Voice → Manage Voices…

	macOS 14–15 (Sonoma–Sequoia):
	  System Settings → Accessibility → Spoken Content → System Voice → Manage Voices…

	macOS 13 (Ventura):
	  System Settings → Accessibility → Spoken Content → System Voice → Customize…
	"""
}
