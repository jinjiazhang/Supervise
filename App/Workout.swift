import AVFoundation
import SwiftUI

@MainActor
final class Workout: ObservableObject {
    enum Phase { case preparing, active, paused, finished, failed }

    let exercise: Exercise
    let target: Int
    let holdSeconds: Int
    let camera = PracticeCamera()
    @Published private(set) var phase = Phase.preparing
    @Published private(set) var message = "正在打开摄像头"
    @Published private(set) var count = 0
    @Published private(set) var needsSettings = false
    private var counter: MotionCounter
    private var generation = 0
    private var missingSince: Double?
    private var previousEvent: MotionEvent?
    private var eventSince = 0.0
    private var showResultUntil = 0.0
    private var lastReminder = -Double.infinity
    private let voice = AVSpeechSynthesizer()
    let spoken: Bool

    init(_ exercise: Exercise, target: Int, spoken: Bool, holdSeconds: Int) {
        self.exercise = exercise
        self.target = target
        self.holdSeconds = holdSeconds
        self.spoken = spoken
        counter = MotionCounter(exercise, holdSeconds: holdSeconds)
    }

    func begin() async {
        generation += 1
        let token = generation
        phase = .preparing
        message = "正在打开摄像头"
        needsSettings = false
        counter.recalibrate()
        missingSince = nil
        lastReminder = -.infinity
        previousEvent = nil
        showResultUntil = 0
        var allowed = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            allowed = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard token == generation else { return }
        guard allowed else {
            needsSettings = true
            fail("请在系统设置里允许相机访问，回来后点重试。")
            return
        }
        UIApplication.shared.isIdleTimerDisabled = true
        if spoken {
            let audio = AVAudioSession.sharedInstance()
            try? audio.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
            try? audio.setActive(true)
        }
        message = "双脚放平，站稳一秒"
        say(exercise.setup + message)
        camera.start { [weak self] body, time in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.process(body, time: time)
            }
        } error: { [weak self] reason in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.fail(reason)
            }
        }
    }

    private func process(_ body: Body, time: Double) {
        let event = counter.update(body, at: time)
        let changed = previousEvent != event
        if changed {
            previousEvent = event
            eventSince = time
        }
        if event != .missing { missingSince = nil }
        switch event {
        case .missing:
            if missingSince == nil { missingSince = time }
            if time - (missingSince ?? time) > 0.7 {
                phase = .preparing
                message = "请让全身和双脚入镜，再站稳"
                if time - lastReminder >= 8 {
                    say(message)
                    lastReminder = time
                }
            }
        case .calibrating:
            phase = .preparing
            message = "双脚放平，站稳一秒"
        case .ready:
            phase = .active
            message = "可以开始了"
            say(exercise == .rise ? "开始，每次保持" + String(holdSeconds) + "秒" : "准备好了，开始")
        case .raised:
            message = "已起跳"
        case .holding(let secondsLeft):
            message = "继续保持，还剩 " + String(secondsLeft) + " 秒"
        case .lowerHeel:
            message = "保持完成，慢慢放下脚跟"
            if changed { say(message) }
        case .correction(let issue):
            message = issue.rawValue
            // Allow the normal ascent through lower heel heights before coaching.
            if time - eventSince >= 0.5 { remind(issue, at: time) }
        case .rejected(let issue):
            message = issue.rawValue
            showResultUntil = time + 1.5
            remind(issue, at: time)
        case .tracking:
            guard time >= showResultUntil else { break }
            message = exercise == .rise ? "站稳后踮起脚跟" : "跟着自己的节奏跳"
        case .counted:
            count = counter.count
            message = "已完成 " + String(count) + " 次"
            if count >= target { finish() }
            else if exercise == .rise || count.isMultiple(of: 10) { say(String(count)) }
        }
    }

    private func remind(_ issue: RiseCorrection, at time: Double) {
        guard time - lastReminder >= 3 else { return }
        say(issue.rawValue)
        lastReminder = time
    }

    func pause() {
        guard phase == .active || phase == .preparing else { return }
        stopCapture()
        phase = .paused
        message = "本组次数已保留"
        say("已暂停")
    }

    func finish() {
        stopCapture()
        phase = .finished
        say("本组完成，共" + String(count) + "次，休息一下")
    }

    func close() {
        stopCapture()
        voice.stopSpeaking(at: .immediate)
        if spoken { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }

    private func fail(_ reason: String) {
        stopCapture()
        phase = .failed
        message = reason
        say(reason)
    }

    private func stopCapture() {
        generation += 1
        camera.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func say(_ words: String) {
        guard spoken else { return }
        voice.stopSpeaking(at: .immediate)
        let line = AVSpeechUtterance(string: words)
        line.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        line.rate = 0.49
        voice.speak(line)
    }
}
