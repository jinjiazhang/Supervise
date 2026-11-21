import Foundation

enum Exercise: String, CaseIterable {
    case rope = "跳绳"
    case rise = "踮脚"

    var symbol: String { self == .rope ? "figure.jumprope" : "figure.stand" }
    var setup: String {
        self == .rope ? "面向手机，确保头顶和双脚都在画面内。" : "侧身站立，让靠近镜头一侧的髋、膝、脚跟和脚尖都露出来。"
    }
}

struct Leg {
    // Vertical coordinates increase toward the floor.
    var hip: Double
    var ankle: Double
    var heel: Double
    var toe: Double
    var quality: Double
    var kneeAngle: Double?

    // All three points must use the same physical image scale on both axes.
    static func angle(hip: CGPoint, knee: CGPoint, ankle: CGPoint) -> Double? {
        let thigh = CGPoint(x: hip.x - knee.x, y: hip.y - knee.y)
        let shin = CGPoint(x: ankle.x - knee.x, y: ankle.y - knee.y)
        let lengths = hypot(thigh.x, thigh.y) * hypot(shin.x, shin.y)
        guard lengths > 0.000001 else { return nil }
        let cosine = (thigh.x * shin.x + thigh.y * shin.y) / lengths
        return acos(min(1, max(-1, cosine))) * 180 / .pi
    }
}

struct Body {
    var left: Leg?
    var right: Leg?
}

enum MotionEvent: Equatable {
    case calibrating, ready, tracking, raised, counted, missing
    case correction(RiseCorrection), rejected(RiseCorrection), holding(secondsLeft: Int), lowerHeel
}

enum RiseCorrection: String {
    case knee = "把膝盖伸直一些"
    case heel = "脚跟再抬高一点"
    case support = "前脚掌贴地，放平后重新开始"
    case early = "保持时间还没到，下一次听到提示再放下"
    case reset = "先把脚跟放平，再开始"
}

/// Evaluate a single repetition using ratios of standing leg length.
private struct HeelRise {
    let holdSeconds: Int
    private var holdStart: Double?
    private var completedHold = false
    private var lastIssue: RiseCorrection?
    private var startedHold = false

    init(seconds: Int) { holdSeconds = seconds }

    mutating func reset() {
        holdStart = nil
        completedHold = false
        startedHold = false
        lastIssue = nil
    }

    mutating func update(lift: Double, toeTravel: Double, hipRise: Double, kneeStraight: Bool,
                         needsLanding: inout Bool, at time: Double) -> MotionEvent {
        if abs(toeTravel) > 0.055 {
            reset()
            needsLanding = true
            return .correction(.support)
        }
        if lift < 0.022 {
            defer { reset(); needsLanding = false }
            if needsLanding { return .tracking }
            if !kneeStraight { return .correction(.knee) }
            if completedHold { return .counted }
            if startedHold { return .rejected(.early) }
            if let lastIssue { return .rejected(lastIssue) }
            return .tracking
        }
        guard !needsLanding else { return .correction(.reset) }
        if !kneeStraight {
            reset()
            lastIssue = .knee
            return .correction(.knee)
        }
        // Once the full hold is verified, descending through the height threshold is expected.
        if completedHold { return .lowerHeel }
        let heightThreshold = holdStart == nil ? 0.075 : 0.065
        guard lift >= heightThreshold, hipRise > 0.012 else {
            holdStart = nil
            lastIssue = .heel
            return .correction(.heel)
        }
        lastIssue = nil
        let start = holdStart ?? time
        holdStart = start
        startedHold = true
        let remaining = Double(holdSeconds) - (time - start)
        if remaining > 0.000001 { return .holding(secondsLeft: Int(ceil(remaining - 0.000001))) }
        completedHold = true
        return .lowerHeel
    }
}

struct MotionCounter {
    static let defaultHoldSeconds = 5
    static let holdRange = 1...30
    let exercise: Exercise
    private var rise: HeelRise
    private(set) var count = 0
    private struct Sample {
        var lift: Double
        var floor: Double
        var support: Double
        var scale: Double
        var kneeAngle: Double?
    }
    private var base: Sample?
    private var restingHeelOffset: Double?
    private var candidate: Sample?
    private var stableSince: Double?
    private var stableFrames = 0
    private var leftSide: Bool?
    private var lastTime: Double?
    private var raisedAt: Double?
    private var lastCount = -Double.infinity
    private var needsLanding = false

    init(_ exercise: Exercise, holdSeconds: Int = MotionCounter.defaultHoldSeconds) {
        self.exercise = exercise
        rise = HeelRise(seconds: min(max(holdSeconds, Self.holdRange.lowerBound), Self.holdRange.upperBound))
    }

    mutating func recalibrate() {
        rise.reset()
        base = nil
        candidate = nil
        stableSince = nil
        stableFrames = 0
        leftSide = nil
        lastTime = nil
        raisedAt = nil
        needsLanding = false
    }

    private mutating func measure(_ body: Body) -> Sample? {
        if exercise == .rope {
            guard let l = body.left, let r = body.right else { return nil }
            return Sample(lift: (l.hip + r.hip) / 2, floor: l.toe, support: r.toe,
                          scale: ((l.ankle - l.hip) + (r.ankle - r.hip)) / 2)
        }
        if leftSide == nil {
            let left = body.left.flatMap { $0.kneeAngle == nil ? nil : $0.quality }
            let right = body.right.flatMap { $0.kneeAngle == nil ? nil : $0.quality }
            guard left != nil || right != nil else { return nil }
            leftSide = (left ?? -1) >= (right ?? -1)
        }
        guard let leg = leftSide == true ? body.left : body.right, let angle = leg.kneeAngle else { return nil }
        return Sample(lift: leg.heel - leg.toe, floor: leg.toe, support: leg.hip,
                      scale: leg.ankle - leg.hip, kneeAngle: angle)
    }

    mutating func update(_ body: Body, at time: Double) -> MotionEvent {
        if let previous = lastTime, time - previous > 0.35 { recalibrate() }
        guard let s = measure(body), s.scale > 0.12 else {
            // Never stitch an ascent before occlusion to a landing after it.
            rise.reset()
            raisedAt = nil
            needsLanding = true
            candidate = nil
            return .missing
        }
        lastTime = time
        guard let b = base else {
            if exercise == .rise {
                if (s.kneeAngle ?? 0) < 158 {
                    candidate = nil
                    return .correction(.knee)
                }
                // After tracking loss, wait for the original resting foot angle.
                // On first setup the child's flat-foot position establishes this reference.
                if let restingHeelOffset, restingHeelOffset - s.lift / s.scale > 0.045 {
                    candidate = nil
                    return .correction(.reset)
                }
            }
            if let c = candidate,
               abs(s.lift - c.lift) < 0.030 * c.scale,
               abs(s.floor - c.floor) < 0.035 * c.scale,
               abs(s.support - c.support) < 0.045 * c.scale {
                stableFrames += 1
                if stableFrames >= 5, time - (stableSince ?? time) >= 0.8 {
                    base = c
                    if exercise == .rise { restingHeelOffset = c.lift / c.scale }
                    needsLanding = false
                    return .ready
                }
            } else {
                candidate = s
                stableFrames = 1
                stableSince = time
            }
            return .calibrating
        }
        let lift = (b.lift - s.lift) / b.scale
        let foot = (b.floor - s.floor) / b.scale
        let support = (b.support - s.support) / b.scale
        if exercise == .rise {
            let kneeStraight = (s.kneeAngle ?? 0) >= max(158, (b.kneeAngle ?? 180) - 15)
            let event = rise.update(lift: lift, toeTravel: foot, hipRise: support, kneeStraight: kneeStraight,
                                    needsLanding: &needsLanding, at: time)
            if event == .counted { count += 1 }
            return event
        }
        let grounded = max(foot, support) < 0.024 && lift < 0.036
        let up = min(foot, support) > 0.043 && lift > 0.038
        if grounded {
            defer { raisedAt = nil; needsLanding = false }
            if let start = raisedAt, !needsLanding,
               time - start >= 0.045,
               time - lastCount >= 0.17 {
                count += 1
                lastCount = time
                return .counted
            }
            return .tracking
        }
        if up && !needsLanding && raisedAt == nil { raisedAt = time }
        if let start = raisedAt, time - start > 0.85 {
            raisedAt = nil
            needsLanding = true
        }
        return raisedAt == nil ? .tracking : .raised
    }
}
