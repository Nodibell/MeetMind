import SwiftUI

struct OnboardingView: View {
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
        .frame(width: 600, height: 450)
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
            Text("Завантаження AI моделей")
                .font(.headline)
            
            Text("Ми завантажуємо Whisper (транскрипція) та Llama 3 (аналіз). Це займе кілька хвилин, оскільки все працює локально.")
                .multilineTextAlignment(.center)
                .font(.subheadline)
                .padding(.horizontal)
            
            VStack(spacing: 10) {
                ProgressView(value: downloadProgress)
                    .progressViewStyle(.linear)
                
                Text("\(Int(downloadProgress * 100))%")
                    .font(.caption)
                    .monospacedDigit()
            }
            .padding(.horizontal, 40)
            
            if !isDownloading {
                Button("Почати завантаження") {
                    startModelDownload()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    private var completionStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("Все готово!")
                .font(.title2, weight: .bold)
            
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
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if downloadProgress < 1.0 {
                downloadProgress += 0.01
            } else {
                timer.invalidate()
                isDownloading = false
            }
        }
    }
}

struct PermissionRow: View {
    let title: String
    let description: String
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
    OnboardingView(onComplete: {})
}
