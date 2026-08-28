import Testing
@testable import DesignSystem

@Test func multiSelectNeverEmpties() {
    // An empty domain filter would render an empty shelf — the control must
    // refuse the last deselection rather than show nothing.
    let last: Set = ["makeup"]
    #expect(Segmented.next(from: last, toggling: "makeup", multi: true) == last)
}

@Test func multiSelectTogglesBothWays() {
    let two: Set = ["makeup", "skincare"]
    #expect(Segmented.next(from: two, toggling: "skincare", multi: true) == ["makeup"])
    #expect(Segmented.next(from: two, toggling: "haircare", multi: true) == ["makeup", "skincare", "haircare"])
}

@Test func singleSelectAlwaysReplaces() {
    #expect(Segmented.next(from: ["everyone"], toggling: "your shade", multi: false) == ["your shade"])
    // re-tapping the active option keeps it selected, never clears it
    #expect(Segmented.next(from: ["everyone"], toggling: "everyone", multi: false) == ["everyone"])
}
