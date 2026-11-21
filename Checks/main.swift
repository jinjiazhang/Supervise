// swiftc App/MotionCounter.swift Checks/main.swift -o /tmp/check-motion && /tmp/check-motion
import Foundation

func legs(_ jump: Double = 0, heel: Double = 0) -> Body {
    let leg = Leg(hip: 0.48 - jump - heel * 0.7, ankle: 0.86 - jump - heel * 0.8,
                  heel: 0.89 - jump - heel, toe: 0.90 - jump, quality: 0.9)
    return Body(left: leg, right: leg)
}

struct Run {
    var counter: MotionCounter
    var time = 0.0
    init(_ mode: Exercise) { counter = MotionCounter(mode) }
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

var rise = Run(.rise)
rise.feed(legs(), frames: 35)
for _ in 0..<3 {
    rise.feed(legs(heel: 0.032), frames: 45)
    rise.feed(legs(), frames: 15)
}
precondition(rise.counter.count == 3, "held heel rise counts once on return")
rise.feed(legs(0.045), frames: 15)
rise.feed(legs(), frames: 30)
precondition(rise.counter.count == 3, "lifting the whole foot")
rise.feed(legs(heel: 0.035), frames: 10)
rise.feed(Body(), frames: 30)
precondition(rise.feed(legs(), frames: 35).contains(.ready))
precondition(rise.counter.count == 3, "loss requires recalibration")
rise.counter.recalibrate()
rise.feed(legs(), frames: 32)
rise.feed(legs(heel: 0.034), frames: 8)
rise.feed(legs(), frames: 10)
precondition(rise.counter.count == 4, "resume retains score")
print("Motion checks passed.")
