// swiftc App/MotionCounter.swift Checks/main.swift -o /tmp/check-motion && /tmp/check-motion
import Foundation

func legs(_ jump: Double = 0, heel: Double = 0, knee: Double? = 176) -> Body {
    let leg = Leg(hip: 0.48 - jump - heel * 0.7, ankle: 0.86 - jump - heel * 0.8,
                  heel: 0.89 - jump - heel, toe: 0.90 - jump, quality: 0.9, kneeAngle: knee)
    return Body(left: leg, right: leg)
}

struct Run {
    var counter: MotionCounter
    var time = 0.0
    init(_ mode: Exercise, seconds: Int = MotionCounter.defaultHoldSeconds) {
        counter = MotionCounter(mode, holdSeconds: seconds)
    }
    @discardableResult
    mutating func feed(_ body: Body, frames: Int) -> [MotionEvent] {
        (0..<frames).map { _ in
            time += 1.0 / 30
            return counter.update(body, at: time)
        }
    }
}

var rope = Run(.rope)
precondition(rope.feed(legs(), frames: 32).contains(.ready))
for _ in 0..<12 {
    rope.feed(legs(0.035), frames: 3)
    rope.feed(legs(), frames: 4)
}
precondition(rope.counter.count == 12, "12 rapid jumps")
rope.feed(legs(0.04), frames: 3)
rope.feed(Body(), frames: 2)
rope.feed(legs(), frames: 10)
precondition(rope.counter.count == 12, "lost landing")
rope.feed(Body(left: legs(0.04).left, right: legs().right), frames: 12)
rope.feed(legs(), frames: 4)
precondition(rope.counter.count == 12, "one-foot step")

let hip = CGPoint(x: 60, y: 90)
let knee = CGPoint(x: 60, y: 150)
precondition(Leg.angle(hip: hip, knee: knee, ankle: CGPoint(x: 60, y: 210)) == 180)
precondition(Leg.angle(hip: hip, knee: knee, ankle: CGPoint(x: 120, y: 150)) == 90)
precondition(Leg.angle(hip: hip, knee: hip, ankle: knee) == nil)

let lifted = legs(heel: 0.036)
let low = legs(heel: 0.016)
let bent = legs(heel: 0.036, knee: 140)
var rise = Run(.rise)
precondition(rise.feed(legs(knee: 145), frames: 35).last == .correction(.knee))
precondition(rise.feed(legs(), frames: 35).contains(.ready))
precondition(rise.feed(lifted, frames: 150).last == .holding(secondsLeft: 1))
precondition(rise.feed(legs(), frames: 1).last == .rejected(.early))
precondition(rise.counter.count == 0, "Just under five seconds cannot count")
precondition(rise.feed(low, frames: 200).last == .correction(.heel))
rise.feed(legs(), frames: 10)
precondition(rise.feed(bent, frames: 200).last == .correction(.knee))
rise.feed(legs(), frames: 10)
precondition(rise.counter.count == 0, "Low heel and bent knee cannot qualify")
for badPosture in [bent, low] {
    rise.feed(lifted, frames: 100)
    rise.feed(badPosture, frames: 10)
    rise.feed(lifted, frames: 100)
    rise.feed(legs(), frames: 10)
    precondition(rise.counter.count == 0, "Partial correct holds must not accumulate")
}
precondition(rise.feed(lifted, frames: 151).last == .lowerHeel)
rise.feed(lifted, frames: 180)
precondition(rise.counter.count == 0, "Still raised")
rise.feed(low, frames: 5)
rise.feed(legs(), frames: 20)
precondition(rise.counter.count == 1, "Gradual lowering after full hold counts once")

rise.feed(lifted, frames: 160)
precondition(rise.feed(legs(heel: 0.036, knee: nil), frames: 3).last == .missing)
rise.feed(legs(), frames: 30)
precondition(rise.counter.count == 1, "Cannot infer unseen landing")
rise.feed(legs(0.045), frames: 180)
rise.feed(legs(), frames: 15)
precondition(rise.counter.count == 1, "Whole foot lifted")
rise.feed(lifted, frames: 120)
rise.time += 4
rise.feed(lifted, frames: 120)
rise.feed(legs(), frames: 35)
precondition(rise.counter.count == 1, "Dropped frames cannot contribute hold time")
rise.feed(lifted, frames: 100)
rise.counter.recalibrate()
rise.feed(legs(), frames: 35)
rise.feed(lifted, frames: 100)
rise.feed(legs(), frames: 10)
precondition(rise.counter.count == 1, "Pause resets hold and retains count")

var custom = Run(.rise, seconds: 2)
custom.feed(legs(), frames: 35)
precondition(custom.feed(lifted, frames: 60).last == .holding(secondsLeft: 1))
precondition(custom.feed(lifted, frames: 1).last == .lowerHeel)
custom.feed(legs(), frames: 5)
precondition(custom.counter.count == 1, "Configured duration applies")
print("Motion checks passed.")
