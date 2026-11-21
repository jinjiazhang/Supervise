import SwiftUI
import AVFoundation

@main
struct PracticeApp: App {
    var body: some Scene { WindowGroup { StartView().preferredColorScheme(.light) } }
}

private let ink = Color(red: 0.07, green: 0.19, blue: 0.15)
private let paper = Color(red: 0.96, green: 0.96, blue: 0.92)
private let lime = Color(red: 0.83, green: 0.97, blue: 0.42)

private struct StartView: View {
    @State private var exercise: Exercise = .rope
    @AppStorage("ropeTarget") private var ropeTarget = 30
    @AppStorage("riseTarget") private var riseTarget = 10
    @AppStorage("voiceOn") private var spoken = true
    @State private var practicing = false

    private var target: Binding<Int> { exercise == .rope ? $ropeTarget : $riseTarget }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Label("小小练习场", systemImage: "figure.run.circle.fill")
                        .font(.headline)
                    Text("今天练什么？").font(.system(size: 36, weight: .black))
                    HStack(spacing: 12) {
                        ForEach(Exercise.allCases, id: \.self) { value in
                            Button {
                                exercise = value
                            } label: {
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack {
                                        Image(systemName: value.symbol).font(.system(size: 31, weight: .medium))
                                        Spacer()
                                        Image(systemName: value == exercise ? "checkmark.circle.fill" : "circle")
                                    }
                                    Text(value.rawValue).font(.title2.bold())
                                }
                                .padding(18).background(value == exercise ? lime : Color.white, in: RoundedRectangle(cornerRadius: 20))
                            }
                            .accessibilityAddTraits(value == exercise ? .isSelected : [])
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Label("本组目标", systemImage: "flag.fill").font(.headline).foregroundStyle(lime)
                        HStack(alignment: .center) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(String(target.wrappedValue))
                                    .font(.system(size: 66, weight: .bold, design: .rounded)).monospacedDigit()
                                Text("次").font(.headline)
                            }
                            Spacer()
                            Stepper("目标次数", value: target, in: 5...200, step: 5)
                                .labelsHidden().colorScheme(.dark)
                        }
                    }
                    .padding(22).foregroundStyle(.white).background(ink, in: RoundedRectangle(cornerRadius: 24))
                    VStack(alignment: .leading, spacing: 14) {
                        Label("手机怎么放", systemImage: "iphone.gen3").font(.headline)
                        Text("把手机竖直固定好。" + exercise.setup)
                            .foregroundStyle(ink.opacity(0.78)).fixedSize(horizontal: false, vertical: true)
                        Divider()
                        Toggle(isOn: $spoken) {
                            Label("中文语音提醒", systemImage: "speaker.wave.2.fill").font(.headline)
                        }.tint(ink)
                    }
                    .padding(18).background(.white, in: RoundedRectangle(cornerRadius: 20))
                }.padding(22)
            }
            Button { practicing = true } label: {
                Label("开始" + exercise.rawValue, systemImage: "play.fill")
            }.buttonStyle(ActionStyle()).padding(.horizontal, 22).padding(.vertical, 10)
        }
        .foregroundStyle(ink).background(paper).buttonStyle(.plain)
        .fullScreenCover(isPresented: $practicing) {
            PracticeView(exercise, target: target.wrappedValue, spoken: spoken)
        }
    }
}

private struct ActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 17)
            .foregroundStyle(.white).background(ink, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

private struct PracticeView: View {
    @StateObject private var workout: Workout
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(_ exercise: Exercise, target: Int, spoken: Bool) {
        _workout = StateObject(wrappedValue: Workout(exercise, target: target, spoken: spoken))
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Label(workout.exercise.rawValue, systemImage: workout.exercise.symbol).font(.title2.bold())
                Spacer()
                Button(workout.phase == .finished || workout.phase == .failed ? "关闭" : "结束本组") {
                    if workout.phase == .finished || workout.phase == .failed { dismiss() } else { workout.finish() }
                }.font(.headline).padding(.vertical, 8)
            }
            switch workout.phase {
            case .active, .preparing:
                CameraPreview(session: workout.camera.session)
                    .background(Color.black).clipShape(RoundedRectangle(cornerRadius: 18))
                    .accessibilityLabel("摄像头实时画面")
                Text(workout.message).font(.headline)
                score
                Button("暂停练习") { workout.pause() }.buttonStyle(ActionStyle())
            case .paused, .failed, .finished:
                Spacer()
                let finished = workout.phase == .finished
                Image(systemName: finished ? "flag.checkered" : workout.phase == .paused ? "pause.fill" : "camera.fill")
                    .font(.largeTitle).frame(width: 84, height: 84).background(lime, in: Circle())
                Text(finished ? "本组完成" : workout.phase == .paused ? "练习已暂停" : "摄像头未就绪")
                    .font(.largeTitle.bold())
                if workout.phase != .failed { score }
                if !finished { Text(workout.message).multilineTextAlignment(.center) }
                Spacer()
                if workout.needsSettings {
                    Button("打开系统设置") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                }
                Button(finished ? "返回练习场" : workout.phase == .paused ? "继续练习" : "重试") {
                    if finished { dismiss() } else { Task { await workout.begin() } }
                }.buttonStyle(ActionStyle())
            }
        }
        .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(ink).background(paper).task { await workout.begin() }
        .onChange(of: scenePhase) { if $0 == .background { workout.pause() } }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.wasInterruptedNotification, object: workout.camera.session)) { _ in workout.pause() }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.runtimeErrorNotification, object: workout.camera.session)) { _ in workout.pause() }
        .onDisappear { workout.close() }
    }

    private var score: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(String(workout.count))
                .font(.system(size: 64, weight: .black, design: .rounded)).monospacedDigit()
            Text("/ " + String(workout.target) + " 次").font(.title3.bold()).foregroundStyle(.secondary)
        }
    }
}

private final class PreviewSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewSurface {
        let view = PreviewSurface()
        view.preview.videoGravity = .resizeAspect
        view.preview.session = session
        return view
    }
    func updateUIView(_ view: PreviewSurface, context: Context) {
        if let connection = view.preview.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }
}
