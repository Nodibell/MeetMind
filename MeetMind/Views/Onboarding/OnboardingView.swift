import SwiftUI
import AVFoundation
import CoreGraphics
import AppKit

@Observable
final class OnboardingViewModel: @unchecked Sendable {
    let transcriptionService: any TranscriptionProvider
    
    var currentStep = 0
    var micPermission = false
    var screenPermission = false
    var downloadProgress: Double = 0.0
    var isDownloading = false
    
    init(transcriptionService: any TranscriptionProvider) {
        self.transcriptionService = transcriptionService
    }
    
    @MainActor
    func updatePermissionStates() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            self.micPermission = true
        }
        if CGPreflightScreenCaptureAccess() {
            self.screenPermission = true
        }
    }
    
    @MainActor
    func requestMicPermission() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            guard let self else { return }
            Task { @MainActor in
                withAnimation {
                    // Always set to true once requested to avoid blocking the user in case of TCC bugs
                    self.micPermission = true
                }
            }
        }
    }
    
    @MainActor
    func requestScreenPermission() {
        let alreadyGranted = CGPreflightScreenCaptureAccess()
        if alreadyGranted {
            withAnimation {
                self.screenPermission = true
            }
            return
        }
        
        let granted = CGRequestScreenCaptureAccess()
        if granted {
            withAnimation {
                self.screenPermission = true
            }
        } else {
            // Always set to true once requested to prevent users from getting stuck due to ad-hoc macOS TCC bugs
            withAnimation {
                self.screenPermission = true
            }
            
            let preflightGranted = CGPreflightScreenCaptureAccess()
            if !preflightGranted {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
    
    @MainActor
    func startModelDownload() {
        isDownloading = true
        downloadProgress = 0.0
        
        subscribeToStateChanges()
        
        Task {
            do {
                try await transcriptionService.initialize(modelName: nil)
            } catch {
                isDownloading = false
            }
        }
    }
    
    @MainActor
    func checkCurrentDownloadState() {
        Task {
            let currentState = await transcriptionService.state
            switch currentState {
            case .downloading(let progress):
                self.downloadProgress = progress
                self.isDownloading = true
                self.subscribeToStateChanges()
            case .loading:
                self.downloadProgress = 0.95
                self.isDownloading = true
                self.subscribeToStateChanges()
            case .ready:
                self.downloadProgress = 1.0
                self.isDownloading = false
            case .error(_):
                self.downloadProgress = 0.0
                self.isDownloading = false
            default:
                break
            }
        }
    }
    
    @MainActor
    private func subscribeToStateChanges() {
        Task {
            await transcriptionService.setOnStateChanged { [weak self] state in
                guard let self else { return }
                Task { @MainActor in
                    switch state {
                    case .downloading(let progress):
                        self.downloadProgress = progress
                        self.isDownloading = true
                    case .loading:
                        self.downloadProgress = 0.95
                        self.isDownloading = true
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
        }
    }
}

struct OnboardingView: View {
    @State private var viewModel: OnboardingViewModel
    
    var onComplete: () -> Void
    
    init(transcriptionService: any TranscriptionProvider, onComplete: @escaping () -> Void) {
        self._viewModel = State(initialValue: OnboardingViewModel(transcriptionService: transcriptionService))
        self.onComplete = onComplete
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 30) {
                header
                
                ZStack {
                    if viewModel.currentStep == 0 {
                        permissionsStep
                    } else if viewModel.currentStep == 1 {
                        modelSetupStep
                    } else {
                        completionStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                footer
            }
            .padding(40)
            
            Button(action: {
                NSApp.terminate(nil)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color.secondary.opacity(0.7))
                    .padding(16)
            }
            .buttonStyle(.plain)
            .help("Вийти з додатка")
        }
        .frame(width: 650, height: 490)
        .background(Theme.Colors.backgroundPrimary)
        .onAppear {
            viewModel.checkCurrentDownloadState()
            viewModel.updatePermissionStates()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.updatePermissionStates()
        }
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
                isGranted: viewModel.micPermission,
                action: requestMicPermission
            )
            
            PermissionRow(
                title: "Запис екрану",
                description: "Необхідно для захоплення системного аудіо (Zoom, Teams)",
                isGranted: viewModel.screenPermission,
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
                ProgressView(value: viewModel.downloadProgress)
                    .progressViewStyle(.linear)
                
                Text("\(Int(viewModel.downloadProgress * 100))%")
                    .font(.caption)
                    .monospacedDigit()
            }
            .padding(.horizontal, 40)
            
            if !viewModel.isDownloading && viewModel.downloadProgress < 1.0 {
                Button("Почати завантаження") {
                    viewModel.startModelDownload()
                }
                .buttonStyle(.borderedProminent)
            } else if viewModel.isDownloading {
                Text("Завантаження моделі з Hugging Face...")
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else if viewModel.downloadProgress >= 1.0 {
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
            if viewModel.currentStep > 0 {
                Button("Назад") {
                    withAnimation { viewModel.currentStep -= 1 }
                }
            }
            
            Spacer()
            
            if viewModel.currentStep < 2 {
                Button("Далі") {
                    withAnimation { viewModel.currentStep += 1 }
                }
                .disabled(viewModel.currentStep == 0 && (!viewModel.micPermission || !viewModel.screenPermission))
                .disabled(viewModel.currentStep == 1 && viewModel.downloadProgress < 1.0)
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
        viewModel.requestMicPermission()
    }
    
    private func requestScreenPermission() {
        viewModel.requestScreenPermission()
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
        var state: TranscriptionService.ServiceState { .notReady }
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
