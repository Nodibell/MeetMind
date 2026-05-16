import SwiftUI

struct RecordingIndicatorView: View {
    @State private var isAnimating = false
    @ObservedObject var state: FloatingIndicatorManager.IndicatorState
    
    var body: some View {
        HStack(spacing: 12) {
            // Siri-style animated border circle
            ZStack {
                Circle()
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [.blue, .purple, .cyan, .blue]),
                            center: .center
                        ),
                        lineWidth: 3
                    )
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .frame(width: 32, height: 32)
                    .opacity(state.isActiveSpeech ? 1 : 0.3)
                    .animation(state.isActiveSpeech ? .linear(duration: 2).repeatForever(autoreverses: false) : .default, value: isAnimating)
                
                if state.isActiveSpeech {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                        .scaleEffect(isAnimating ? 1.2 : 0.8)
                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isAnimating)
                } else {
                    Circle()
                        .fill(Color.gray)
                        .frame(width: 8, height: 8)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(state.isActiveSpeech ? "Запис..." : "Очікування...")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                
                if let speaker = state.speakerName {
                    Text(speaker)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.8))
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .clipShape(Capsule())
        )
        .onAppear {
            isAnimating = true
        }
    }
}

// Helper for Blur Effect
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

#Preview {
    RecordingIndicatorView(state: FloatingIndicatorManager.IndicatorState())
        .padding()
        .background(Color.black)
}
