import SwiftUI

struct RecordingIndicatorView: View {
    @State private var isAnimating = false
    @State private var isHovered = false
    @State private var isExpanded = false
    @ObservedObject var state: FloatingIndicatorManager.IndicatorState
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Animated Indicator
                indicatorCircle
                
                // Status & Time
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(state.isPaused ? String(localized: "Пауза") : (state.isActiveSpeech ? String(localized: "Запис") : String(localized: "Тиша")))
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)
                        
                        Circle()
                            .fill(state.isPaused ? .orange : (state.isActiveSpeech ? .red : .gray))
                            .frame(width: 4, height: 4)
                        
                        Text(formatTime(state.elapsedTime))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                    }
                    .foregroundColor(.white)
                    
                    if let speaker = state.speakerName {
                        Text(speaker)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                .frame(minWidth: 80, alignment: .leading)
                .layoutPriority(1)
                
                Spacer(minLength: 8)
                
                // Controls
                HStack(spacing: 8) {
                    if isHovered || state.isPaused {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                if state.isPaused {
                                    state.onResume?()
                                } else {
                                    state.onPause?()
                                }
                            }
                        } label: {
                            Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 12))
                                .frame(width: 24, height: 24)
                                .background(state.isPaused ? Color.orange.opacity(0.3) : Color.white.opacity(0.2))
                                .clipShape(Circle())
                                .scaleEffect(isHovered ? 1.0 : 0.8)
                        }
                        .buttonStyle(.plain)
                        .help(state.isPaused ? String(localized: "Продовжити") : String(localized: "Пауза"))
                        
                        Button {
                            withAnimation(.easeIn(duration: 0.2)) {
                                state.onStop?()
                            }
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10))
                                .frame(width: 24, height: 24)
                                .background(Color.red.opacity(0.6))
                                .clipShape(Circle())
                                .scaleEffect(isHovered ? 1.0 : 0.8)
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "Зупинити"))
                    }
                    
                    Button {
                        withAnimation(.spring()) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    
                    if isHovered {
                        Button {
                            state.onHide?()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .frame(width: 18, height: 18)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .foregroundColor(.white)
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Divider().background(Color.white.opacity(0.2))
                    
                    if let transcript = state.lastTranscript, !transcript.isEmpty {
                        Text(transcript)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(String(localized: "Очікування транскрипту..."))
                            .font(.system(size: 10).italic())
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 300)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
    
    private var indicatorCircle: some View {
        ZStack {
            Circle()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [.blue, .purple, .cyan, .blue]),
                        center: .center
                    ),
                    lineWidth: 2.5
                )
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .frame(width: 28, height: 28)
                .opacity(state.isActiveSpeech && !state.isPaused ? 1 : 0.3)
                .animation(state.isActiveSpeech && !state.isPaused ? .linear(duration: 2).repeatForever(autoreverses: false) : .default, value: isAnimating)
            
            if state.isActiveSpeech && !state.isPaused {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .scaleEffect(isAnimating ? 1.2 : 0.8)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isAnimating)
            } else {
                Circle()
                    .fill(state.isPaused ? Color.orange : Color.gray)
                    .frame(width: 8, height: 8)
            }
        }
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: seconds) ?? "00:00"
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
