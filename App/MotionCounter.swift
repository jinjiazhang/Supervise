import Foundation

enum Exercise: String, CaseIterable {
    case rope = "跳绳"
    case rise = "踮脚"

    var symbol: String { self == .rope ? "figure.jumprope" : "figure.stand" }
    var setup: String {
        self == .rope ? "面向手机，确保头顶和双脚都在画面内。" : "侧身站立，让靠近镜头一侧的脚跟和脚尖都露出来。"
    }
}

struct Leg {
    // Vertical coordinates increase toward the floor.
    var hip: Double
    var ankle: Double
    var heel: Double
    var toe: Double
    var quality: Double
}

struct Body {
    var left: Leg?
    var right: Leg?
}

enum MotionEvent: Equatable {
    case calibrating, ready, tracking, raised, counted, missing
}

struct MotionCounter {
    let exercise: Exercise
    private(set) var count = 0
    private struct Sample {
        var lift: Double
        var floor: Double
        var support: Double
        var scale: Double
    }
    private var base: Sample?
    private var candidate: Sample?
    private var stableSince: Double?
    private var stableFrames = 0
    private var leftSide: Bool?
    private var lastTime: Double?
    private var raisedAt: Double?
    private var lastCount = -Double.infinity
    private var needsLanding = false

    init(_ exercise: Exercise) { self.exercise = exercise }

    mutating func recalibrate() {
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
            guard body.left != nil || body.right != nil else { return nil }
            leftSide = (body.left?.quality ?? -1) >= (body.right?.quality ?? -1)
        }
        guard let leg = leftSide == true ? body.left : body.right else { return nil }
        return Sample(lift: leg.heel - leg.toe, floor: leg.toe, support: leg.hip,
                      scale: leg.ankle - leg.hip)
    }

    mutating func update(_ body: Body, at time: Double) -> MotionEvent {
        if let previous = lastTime, time - previous > 0.35 { recalibrate() }
        guard let s = measure(body), s.scale > 0.12 else {
            // Never stitch an ascent before occlusion to a landing after it.
            raisedAt = nil
            needsLanding = true
            candidate = nil
            return .missing
        }
        lastTime = time
        guard let b = base else {
            if let c = candidate,
               abs(s.lift - c.lift) < 0.030 * c.scale,
               abs(s.floor - c.floor) < 0.035 * c.scale,
               abs(s.support - c.support) < 0.045 * c.scale {
                stableFrames += 1
                if stableFrames >= 5, time - (stableSince ?? time) >= 0.8 {
                    base = c
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
        let jump = exercise == .rope
        let grounded = jump ? max(foot, support) < 0.024 && lift < 0.036 : lift < 0.022 && abs(foot) < 0.055
        let up = jump ? min(foot, support) > 0.043 && lift > 0.038
                      : lift > 0.052 && abs(foot) < 0.05 && support > 0.012

        if !jump && abs(foot) > 0.075 {
            raisedAt = nil
            needsLanding = true
        }
        if grounded {
            defer { raisedAt = nil; needsLanding = false }
            if let start = raisedAt, !needsLanding,
               time - start >= (jump ? 0.045 : 0.16),
               time - lastCount >= (jump ? 0.17 : 0.42) {
                count += 1
                lastCount = time
                return .counted
            }
            return .tracking
        }
        if up && !needsLanding && raisedAt == nil { raisedAt = time }
        if jump, let start = raisedAt, time - start > 0.85 {
            raisedAt = nil
            needsLanding = true
        }
        return raisedAt == nil ? .tracking : .raised
    }
}
