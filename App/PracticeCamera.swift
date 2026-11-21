import AVFoundation
import MediaPipeTasksVision

final class PracticeCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "practice.camera", qos: .userInitiated)
    private let frames = AVCaptureVideoDataOutput()
    private var detector: PoseLandmarker?
    private var onBody: ((Body, Double) -> Void)?
    private var onError: ((String) -> Void)?
    private var lastStamp = -1
    private var consecutiveErrors = 0

    func start(body: @escaping (Body, Double) -> Void, error: @escaping (String) -> Void) {
        queue.async {
            do {
                if self.detector == nil {
                    guard let path = Bundle.main.path(forResource: "pose_landmarker_lite", ofType: "task") else {
                        throw CameraProblem("动作识别模型缺失，请重新安装。")
                    }
                    let options = PoseLandmarkerOptions()
                    options.baseOptions.modelAssetPath = path
                    options.runningMode = .video
                    self.detector = try PoseLandmarker(options: options)
                }
                if self.session.inputs.isEmpty { try self.configure() }
                self.onBody = body
                self.onError = error
                self.consecutiveErrors = 0
                self.session.startRunning()
                if !self.session.isRunning { throw CameraProblem("摄像头未能启动，请重试。") }
            } catch let failure {
                error(failure.localizedDescription)
            }
        }
    }

    private func configure() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video) else {
            throw CameraProblem("没有找到摄像头，请在 iPhone 真机上练习。")
        }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        guard session.canAddInput(input) else { throw CameraProblem("摄像头暂时不可用。") }
        session.addInput(input)
        guard session.canAddOutput(frames) else {
            session.removeInput(input)
            throw CameraProblem("暂时无法读取摄像头画面。")
        }
        frames.alwaysDiscardsLateVideoFrames = true
        frames.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        frames.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(frames)
        if let connection = frames.connection(with: .video) {
            connection.videoOrientation = .portrait
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }
    }

    func stop() {
        queue.async {
            self.onBody = nil
            self.onError = nil
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let detector, let onBody else { return }
        let stamp = Int(CMSampleBufferGetPresentationTimeStamp(buffer).seconds * 1000)
        guard stamp > lastStamp else { return }
        lastStamp = stamp
        do {
            let image = try MPImage(sampleBuffer: buffer)
            let result = try detector.detect(videoFrame: image, timestampInMilliseconds: stamp)
            let points = result.landmarks.first ?? []
            guard let pixels = CMSampleBufferGetImageBuffer(buffer) else {
                onBody(Body(), Double(stamp) / 1000)
                return
            }
            let size = CGSize(width: CVPixelBufferGetWidth(pixels), height: CVPixelBufferGetHeight(pixels))
            let body = Body(left: Self.leg(points, side: 0, size: size), right: Self.leg(points, side: 1, size: size))
            consecutiveErrors = 0
            onBody(body, Double(stamp) / 1000)
        } catch {
            consecutiveErrors += 1
            onBody(Body(), Double(stamp) / 1000)
            if consecutiveErrors == 12 { onError?("画面识别中断，请重新开始。") }
        }
    }

    private static func leg(_ points: [NormalizedLandmark], side: Int, size: CGSize) -> Leg? {
        guard points.count >= 33 else { return nil }
        let joints = [23, 27, 29, 31].map { points[$0 + side] }
        guard joints.allSatisfy({ (0.01...0.99).contains($0.x) && (0.01...0.99).contains($0.y) }) else { return nil }
        let quality = joints.map { min($0.visibility?.doubleValue ?? 0, $0.presence?.doubleValue ?? 1) }.min() ?? 0
        guard quality >= 0.52 else { return nil }
        let knee = points[25 + side]
        let kneeVisible = (0.01...0.99).contains(knee.x) && (0.01...0.99).contains(knee.y)
            && min(knee.visibility?.doubleValue ?? 0, knee.presence?.doubleValue ?? 1) >= 0.52
        func pixelPoint(_ joint: NormalizedLandmark) -> CGPoint {
            CGPoint(x: CGFloat(joint.x) * size.width, y: CGFloat(joint.y) * size.height)
        }
        let kneeAngle = kneeVisible ? Leg.angle(hip: pixelPoint(joints[0]), knee: pixelPoint(knee),
                                               ankle: pixelPoint(joints[1])) : nil
        return Leg(hip: Double(joints[0].y), ankle: Double(joints[1].y),
                   heel: Double(joints[2].y), toe: Double(joints[3].y), quality: quality, kneeAngle: kneeAngle)
    }
}

private struct CameraProblem: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
