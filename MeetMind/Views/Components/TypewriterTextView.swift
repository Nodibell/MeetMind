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
    TypewriterTextView(fullText: "Привіт, це тест посимвольного виводу тексту.", isStreaming: true)
        .padding()
}
