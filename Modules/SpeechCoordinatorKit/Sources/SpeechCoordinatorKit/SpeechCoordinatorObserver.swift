//
//  SpeechCoordinatorObserver.swift
//  NetNewsWire
//

import Foundation

@MainActor
public protocol SpeechCoordinatorObserver: AnyObject {
	func speechCoordinatorDidUpdate(_ coordinator: SpeechCoordinator)
}
