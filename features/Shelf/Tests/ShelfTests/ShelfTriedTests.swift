import DataKit
import Testing
@testable import Shelf

// GLO-87's surface binary: the two icons collapse four statuses into
// saved-or-tried. The mapping is the load-bearing rule — chips and the
// status detail both gate on it, so a wrong answer here hides a section.

@Test func triedCoversEverythingButWantToTry() {
    #expect(!ItemStatus.wantToTry.isTried)
    #expect(ItemStatus.own.isTried)
    #expect(ItemStatus.finished.isTried)
    #expect(ItemStatus.repurchased.isTried)
}
