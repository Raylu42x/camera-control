import CoreImage
import QuartzCore

/// Emoji reactions that rain down or float up over the video for a few seconds.
final class ParticleSystem {
    private struct Particle {
        var emoji: String
        var pos: CGPoint
        var vel: CGVector
        var size: CGFloat
        var spin: CGFloat
        var born: Double
        var life: Double
    }

    private let lock = NSLock()
    private var particles: [Particle] = []
    private var lastTime: Double?

    func burst(_ reaction: Reaction) {
        let now = CACurrentMediaTime()
        let W = canvasSize.width, H = canvasSize.height
        let count = reaction.fallsDown ? 70 : 28
        var new: [Particle] = []
        for i in 0..<count {
            let emoji = reaction.emojis[i % reaction.emojis.count]
            let delay = Double.random(in: 0...0.9)
            if reaction.fallsDown {
                new.append(Particle(emoji: emoji, pos: CGPoint(x: .random(in: 0...W), y: H + .random(in: 20...200)),
                                    vel: CGVector(dx: .random(in: -60...60), dy: .random(in: -320 ... -160)),
                                    size: .random(in: 34...70), spin: .random(in: -3...3), born: now + delay, life: 3.6))
            } else {
                new.append(Particle(emoji: emoji, pos: CGPoint(x: .random(in: W * 0.55...W - 60), y: -60),
                                    vel: CGVector(dx: .random(in: -50...30), dy: .random(in: 180...320)),
                                    size: .random(in: 50...96), spin: .random(in: -0.6...0.6), born: now + delay, life: 3.2))
            }
        }
        lock.lock(); particles += new; lock.unlock()
    }

    /// Advances the simulation and composites live particles over `image`.
    func render(over image: CIImage) -> CIImage {
        let now = CACurrentMediaTime()
        lock.lock(); defer { lock.unlock() }
        let dt = min(now - (lastTime ?? now), 0.1)
        lastTime = now
        guard !particles.isEmpty else { return image }
        particles.removeAll { now - $0.born > $0.life }
        var out = image
        for i in particles.indices {
            let age = now - particles[i].born
            guard age >= 0 else { continue }
            particles[i].pos.x += particles[i].vel.dx * dt
            particles[i].pos.y += particles[i].vel.dy * dt
            // Gentle wobble so floating emoji drift side to side.
            particles[i].pos.x += CGFloat(sin(age * 3 + Double(i))) * 0.8
            let p = particles[i]
            let fade = CGFloat(min(1, (p.life - age) / 0.6))
            let sprite = EmojiCache.shared.image(p.emoji)
                .placed(center: p.pos, width: p.size, rotation: p.spin * CGFloat(age) * 0.5)
            out = (fade < 1 ? sprite.withAlpha(fade) : sprite).composited(over: out)
        }
        return out
    }
}
