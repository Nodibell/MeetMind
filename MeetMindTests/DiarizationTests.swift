
import XCTest
@testable import MeetMind
import SpeakerKit

final class DiarizationTests: XCTestCase {

    func testSpeakerMatching() {
        // Mock data
        let textSegments = [
            MeetingTranscriptSegment(startTime: 0, endTime: 2, text: "Hello", speakerID: nil),
            MeetingTranscriptSegment(startTime: 3, endTime: 5, text: "How are you?", speakerID: nil)
        ]
        
        let speakerSegments = [
            SpeakerKit.SpeakerSegment(startTime: 0, endTime: 2.5, speakerID: "Speaker 1"),
            SpeakerKit.SpeakerSegment(startTime: 2.6, endTime: 6, speakerID: "Speaker 2")
        ]
        
        // Match (this logic is currently in TranscriptionService, which is an actor)
        // For testing, I'll test the logic itself if I can make it static or separate
    }
}
