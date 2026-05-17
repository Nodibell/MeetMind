import SwiftUI

struct OnboardingView: View {
    let transcriptionService: any TranscriptionProvider
    
    @State private var currentStep = 0
    @State private var micPermission = false
    @State private var screenPermission = false
    @State private var downloadProgress: Double = 0
    @State private var isDownloading = false
    
    var onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            header
            
            ZStack {
                if currentStep == 0 {
                    permissionsStep
                } else if currentStep == 1 {
                    modelSetupStep
                } else {
                    completionStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            footer
        }
        .padding(40)
        .frame(width: 650, height: 490)
        .background(Theme.Colors.backgroundPrimary)
    }
    
    private var header: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .frame(width: 64, height: 64)
            
            Text("Ласкаво просимо до MeetMind")
                .font(.system(size: 24, weight: .bold))
            
            Text("Налаштуймо все для професійної роботи")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var permissionsStep: some View {
        VStack(spacing: 20) {
            PermissionRow(
                title: "Мікрофон",
                description: "Необхідно для запису вашого голосу",
                isGranted: micPermission,
                action: requestMicPermission
            )
            
            PermissionRow(
                title: "Запис екрану",
                description: "Необхідно для захоплення системного аудіо (Zoom, Teams)",
                isGranted: screenPermission,
                action: requestScreenPermission
            )
        }
    }
    
    private var modelSetupStep: some View {
        VStack(spacing: 25) {
            Text("Завантаження моделі AI")
                .font(.headline)
            
            Text("Ми завантажуємо модель Whisper для швидкої та приватної локальної транскрипції голосу на вашому Mac. Це займе кілька хвилин.")
                .multilineTextAlignment(.center)
                .font(.subheadline)
                .padding(.horizontal)
                .fixedSize(horizontal: false, vertical: true)
            
            VStack(spacing: 10) {
                ProgressView(value: downloadProgress)
                    .progressViewStyle(.linear)
                
                Text("\(Int(downloadProgress * 100))%")
                    .font(.caption)
                    .monospacedDigit()
            }
            .padding(.horizontal, 40)
            
            if !isDownloading && downloadProgress < 1.0 {
                Button("Почати завантаження") {
                    startModelDownload()
                }
                .buttonStyle(.borderedProminent)
            } else if isDownloading {
                Text("Завантаження моделі з Hugging Face...")
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else if downloadProgress >= 1.0 {
                Text("Завантаження завершено")
                    .foregroundColor(.green)
                    .font(.subheadline)
            }
        }
    }
    
    private var completionStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("Все готово!")
                .font(.title2.bold())
            
            Text("Тепер ваші наради будуть автоматично транскрибуватися та аналізуватися професійним AI асистентом.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
    
    private var footer: some View {
        HStack {
            if currentStep > 0 {
                Button("Назад") {
                    withAnimation { currentStep -= 1 }
                }
            }
            
            Spacer()
            
            if currentStep < 2 {
                Button("Далі") {
                    withAnimation { currentStep += 1 }
                }
                .disabled(currentStep == 0 && (!micPermission || !screenPermission))
                .disabled(currentStep == 1 && downloadProgress < 1.0)
                .buttonStyle(.borderedProminent)
            } else {
                Button("Почати роботу") {
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    // MARK: - Actions
    
    private func requestMicPermission() {
        // Real implementation would use AVCaptureDevice.requestAccess
        withAnimation { micPermission = true }
    }
    
    private func requestScreenPermission() {
        // Real implementation would trigger SCStream check
        withAnimation { screenPermission = true }
    }
    
    private func startModelDownload() {
        isDownloading = true
        downloadProgress = 0.0
        
        Task {
            await transcriptionService.setOnStateChanged { state in
                Task { @MainActor in
                    switch state {
                    case .downloading(let progress):
                        self.downloadProgress = progress
                    case .loading:
                        self.downloadProgress = 0.95
                    case .ready:
                        self.downloadProgress = 1.0
                        self.isDownloading = false
                    case .error(let errorMsg):
                        self.isDownloading = false
                        AppLogger.error("Error downloading model in onboarding: \(errorMsg)")
                    default:
                        break
                    }
                }
            }
            
            do {
                try await transcriptionService.initialize(modelName: nil)
            } catch {
                await MainActor.run {
                    self.isDownloading = false
                }
            }
        }
    }
}

struct PermissionRow: View {
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    let isGranted: Bool
    let action: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(description).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if isGranted {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            } else {
                Button("Надати доступ", action: action)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
}

#Preview {
    struct MockTranscriptionProvider: TranscriptionProvider {
        var isReady: Bool { false }
        func initialize(modelName: String?) async throws {}
        func transcribeLive(samples: [Float], offset: TimeInterval) async throws -> [MeetingTranscriptSegment] { [] }
        func transcribeFile(at url: URL) async throws -> MeetingTranscriptDocument {
            MeetingTranscriptDocument(meetingId: UUID(), createdAt: Date(), language: "en", segments: [])
        }
        func unloadModels() async {}
        func setOnStateChanged(_ callback: (@Sendable (TranscriptionService.ServiceState) -> Void)?) async {}
    }
    
    return OnboardingView(transcriptionService: MockTranscriptionProvider(), onComplete: {})
}
