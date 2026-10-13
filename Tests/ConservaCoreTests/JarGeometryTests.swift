import CoreGraphics
import Testing
@testable import ConservaCore

struct JarGeometryTests {
    @Test func localAndDesignAreInverse() {
        let p = CGPoint(x: 37, y: 121)
        #expect(JarGeometry.design(JarGeometry.local(p)) == p)
        #expect(JarGeometry.local(JarGeometry.pivot) == .zero)
        // y-up: the mouth is above the pivot, the bottom below it.
        #expect(JarGeometry.local(x: 150, y: JarGeometry.mouthY).y > 0)
        #expect(JarGeometry.local(x: 150, y: JarGeometry.bottomY).y < 0)
    }

    @Test func theChainIsSymmetricAndOpenAtTheMouth() {
        let chain = JarGeometry.innerChain
        for (a, b) in zip(chain, chain.reversed()) {
            #expect(abs((a.x - 150) + (b.x - 150)) < 0.001)
            #expect(a.y == b.y)
        }
        #expect(chain.first!.y == JarGeometry.mouthY)
        #expect(chain.last!.x - chain.first!.x == JarGeometry.mouthHalfWidth * 2)
    }

    @Test func twoPhotosSideBySidePassTheNeck() {
        #expect(JarGeometry.size(of: .image).width * 2 < JarGeometry.mouthHalfWidth * 2)
        #expect(JarGeometry.size(of: .document).width * 2 < JarGeometry.mouthHalfWidth * 2)
        // The long ones go through the neck on end.
        for kind in [ItemKind.link, .text, .file] {
            #expect(JarGeometry.size(of: kind).height < JarGeometry.mouthHalfWidth * 2)
        }
    }

    @Test func anyThingPassesTheNeckAtAnyAngle() {
        // The physics keeps a thin skin, a unit or two, round every body: leave room for it on both ends.
        let skin: CGFloat = 6
        for s in JarGeometry.allSizes {
            #expect(hypot(s.width, s.height) + skin < JarGeometry.mouthHalfWidth * 2)
        }
    }

    @Test func twoLongOnesLieSideBySideOnTheBottom() {
        for s in JarGeometry.allSizes {
            #expect(s.width * 2 <= 244)
        }
    }

    @Test func restingSpotsSitInsideWithoutOverlapping() {
        let all = JarGeometry.allSizes
        let mixed = (0..<JarGeometry.maxLoose).map { all[$0 % all.count] }
        let alone = all.map { Array(repeating: $0, count: JarGeometry.maxLoose) }
        for sizes in [mixed] + alone {
            let spots = JarGeometry.restingSpots(for: sizes)
            // A jar's worth settles in at launch with nothing left waiting.
            #expect(spots.count == JarGeometry.maxLoose)
            let rects = zip(spots, sizes).map { CGRect(x: $0.x - $1.width / 2, y: $0.y - $1.height / 2, width: $1.width, height: $1.height) }
            for r in rects {
                #expect(r.minX >= 28)
                #expect(r.maxX <= 272)
                #expect(r.maxY <= 396)
                // Below the shoulders, where the jar is full width.
                #expect(r.minY >= JarGeometry.shoulderY)
                #expect(JarGeometry.isInside(CGPoint(x: r.midX, y: r.midY)))
            }
            for i in rects.indices {
                for j in rects.indices where j > i {
                    #expect(!rects[i].intersects(rects[j]))
                }
            }
        }
    }

    @Test func whatDoesNotFitBelowTheShouldersIsLeftOut() {
        let many = Array(repeating: JarGeometry.size(of: .file), count: 30)
        let spots = JarGeometry.restingSpots(for: many)
        #expect(spots.count < many.count)
        #expect(spots.allSatisfy { $0.y - JarGeometry.size(of: .file).height / 2 >= JarGeometry.shoulderY })
    }
}
