import SwiftUI

struct MainWindowView: View {
    @ObservedObject var controller: DictationController

    var body: some View {
        TabView {
            DashboardView(controller: controller)
                .tabItem {
                    Label("Dashboard", systemImage: "waveform")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

struct DashboardView: View {
    @ObservedObject var controller: DictationController

    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "mic.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundStyle(controller.state == .listening ? .red : .secondary)
                .symbolEffect(.pulse, isActive: controller.state == .listening)

            Text(statusTitle)
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text(statusSubtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if controller.state == .listening && !controller.partialTranscript.isEmpty {
                Text(controller.partialTranscript)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
            }

            Button(action: {
                controller.toggle()
            }) {
                Text(controller.state == .listening ? "Stop Dictation" : "Start Dictation")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(controller.state == .listening ? .red : .accentColor)
            .disabled(!controller.isReady && controller.state == .idle)

            if let err = controller.lastError {
                VStack(spacing: 8) {
                    Text("⚠︎ Error: \(err)")
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                    Button("Grant Accessibility & Retry") {
                        HotkeyManager.requestAccessibilityPermission()
                        controller.retryHotkey()
                    }
                }
                .padding(.top)
            }

            Spacer()
        }
        .padding(40)
    }

    private var statusTitle: String {
        switch controller.state {
        case .idle: return controller.isReady ? "Ready to Dictate" : "Loading Model…"
        case .listening: return "Listening"
        case .transcribing: return "Transcribing"
        case .cleaning: return "Formatting"
        case .error: return "Error"
        }
    }

    private var statusSubtitle: String {
        switch controller.state {
        case .idle: return controller.isReady ? "Press Control+~ anywhere to start dictating." : "Warming up Whisper model in memory."
        case .listening: return "Speak now. Press Control+~ when you're finished."
        case .transcribing: return "Converting your speech to text…"
        case .cleaning: return "Applying grammar, punctuation, and formatting…"
        case .error(let m): return m
        }
    }
}
