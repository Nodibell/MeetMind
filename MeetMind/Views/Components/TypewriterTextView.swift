//
//  TypewriterTextView.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 11.05.2026.
//

import SwiftUI

/// A view that animates text appearing character by character.
/// It intelligently handles string updates (like Whisper refinements) by finding
/// the common prefix and only animating the new suffix, preventing full-string flickering.
struct TypewriterTextView: View {
    let fullText: String
    var isStreaming: Bool = true
    var delayMilliseconds: UInt64 = 15
    
    @State private var displayedText: String = ""
    
    var body: some View {
        Text(displayedText)
            .textSelection(.enabled)
            .task(id: fullText) {
                guard isStreaming else {
                    displayedText = fullText
                    return
                }
                
                await animateText(to: fullText)
            }
            .onChange(of: isStreaming) { _, newValue in
                if !newValue {
                    displayedText = fullText
                }
            }
    }
    
    private func animateText(to targetText: String) async {
        // If we're starting fresh, jump straight to animation
        if displayedText.isEmpty {
            for char in targetText {
                if Task.isCancelled { break }
                displayedText.append(char)
                try? await Task.sleep(nanoseconds: delayMilliseconds * 1_000_000)
            }
            return
        }
        
        // If text was updated (e.g. Whisper refined a word), find common prefix
        let currentChars = Array(displayedText)
        let targetChars = Array(targetText)
        
        var commonPrefixLength = 0
        let minLength = min(currentChars.count, targetChars.count)
        
        while commonPrefixLength < minLength && currentChars[commonPrefixLength] == targetChars[commonPrefixLength] {
            commonPrefixLength += 1
        }
        
        // If the new text is completely different, or shorter than current, snap back
        if commonPrefixLength < currentChars.count {
            displayedText = String(targetChars.prefix(commonPrefixLength))
        }
        
        // Animate the remaining new characters
        for i in commonPrefixLength..<targetChars.count {
            if Task.isCancelled { break }
            displayedText.append(targetChars[i])
            try? await Task.sleep(nanoseconds: delayMilliseconds * 1_000_000)
        }
    }
}

#Preview {
    struct AnimatedPreviewWrapper: View {
        @State private var text = ""
        let phrases = [
            "Hi! This is a demo of the typewriter effect.",
            "MeetMind analyzes your meetings in real time.",
            "Create structured resumes and tasks in seconds.",
            "Local MLX models run right on your Mac!"
        ]
        @State private var phraseIndex = 0
        
        var body: some View {
            VStack(alignment: .leading) {
                TypewriterTextView(fullText: text, isStreaming: true, delayMilliseconds: 25)
                    .font(.system(.title3, design: .rounded))
                    .frame(height: 80, alignment: .topLeading)
                    .padding()
            }
            .frame(width: 450, height: 120)
            .task {
                while true {
                    let targetText = phrases[phraseIndex]
                    // Type out phrase
                    for i in 1...targetText.count {
                        if Task.isCancelled { return }
                        text = String(targetText.prefix(i))
                        try? await Task.sleep(nanoseconds: 40_000_000) // 40ms per character
                    }
                    
                    // Stay fully displayed
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    
                    // Backspace deletion animation
                    for i in (0...targetText.count).reversed() {
                        if Task.isCancelled { return }
                        text = String(targetText.prefix(i))
                        try? await Task.sleep(nanoseconds: 15_000_000) // 15ms per character backspace
                    }
                    
                    // Pause before next phrase
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    
                    phraseIndex = (phraseIndex + 1) % phrases.count
                }
            }
        }
    }
    
    return AnimatedPreviewWrapper()
}
