//
//  AppRouter.swift
//  MeetMind
//
//  Owns all top-level navigation state for the app.
//  ContentView observes this object instead of managing multiple @State booleans.
//

import SwiftUI

// MARK: - AppRouter

/// Single source of truth for top-level navigation destinations.
///
/// Replaces the five `@State` booleans previously living in `ContentView`:
/// `isShowingGlobalSearch`, `isShowingActionItems`, `isShowingRecording`,
/// `selectedMeetingID`, and `columnVisibility`.
@Observable
final class AppRouter {

    // MARK: - Destination

    enum Destination: Equatable {
        /// The new-recording screen (default on launch)
        case recording
        /// A completed meeting's detail view
        case meeting(UUID, highlightedSegmentID: UUID? = nil)
        /// Full-text / semantic global search panel
        case globalSearch
        /// Aggregated action items view
        case actionItems
        /// Q&A chat for a group of meetings using RAG
        case groupChat(UUID)
        /// Empty welcome screen (no selection)
        case welcome
    }

    // MARK: - State

    var current: Destination = .recording
    var columnVisibility: NavigationSplitViewVisibility = .all

    // MARK: - Navigation

    func navigate(to destination: Destination) {
        current = destination
    }

    /// Called when a recording finishes. Transitions to the meeting detail view.
    func navigateAfterRecordingComplete(meetingID: UUID) {
        current = .meeting(meetingID, highlightedSegmentID: nil)
    }

    /// Resets to a fresh recording session.
    func startNewRecording() {
        current = .recording
    }

    // MARK: - Convenience Queries

    var isShowingRecording: Bool {
        current == .recording
    }

    var selectedMeetingID: UUID? {
        switch current {
        case .meeting(let id, _): return id
        case .groupChat(let id): return id
        case .globalSearch: return UUID.globalSearch
        case .actionItems: return UUID.actionItems
        default: return nil
        }
    }
}
