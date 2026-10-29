import Foundation
import RealityKit
import Testing
@testable import Bina

@MainActor
struct SpatialPrototypeStateTests {
    @Test func startsClosedWithRestoredMetadata() {
        let saved = SavedPlacement(anchorID: UUID())
        let store = StubPlacementStore(placement: saved)
        let prototype = SpatialPrototype(store: store)

        #expect(prototype.spaceState == .closed)
        #expect(prototype.trackingState == .idle)
        #expect(prototype.savedPlacement == saved)
        #expect(prototype.hasSavedPlacement)
        #expect(!prototype.anchorIsTracked)
        #expect(!prototype.deviceIsTracked)
        #expect(!prototype.contentEntity.isEnabled)
        #expect(!prototype.storageNeedsReset)
        #expect(store.loadCount == 1)
    }

    @Test func startsWithoutInventingPlacementWhenStorageIsEmpty() {
        let prototype = SpatialPrototype(store: StubPlacementStore())

        #expect(prototype.savedPlacement == nil)
        #expect(!prototype.hasSavedPlacement)
        #expect(!prototype.storageNeedsReset)
        #expect(prototype.message == nil)
        #expect(!prototype.canPlace)
    }

    @Test func unreadableStorageBlocksReplacementUntilReset() async {
        let store = StubPlacementStore()
        store.failsLoad = true
        let prototype = SpatialPrototype(store: store)
        #expect(prototype.storageNeedsReset)
        #expect(prototype.message != nil)

        #expect(prototype.beginOpening())
        prototype.spaceDidAppear()
        #expect(!prototype.canPlace)
        await prototype.placeInFront()

        #expect(store.saveCount == 0)
        #expect(store.clearCount == 0)
        #expect(prototype.storageNeedsReset)
    }

    @Test func openingRejectsDuplicateAndIncompatibleTransitions() {
        let prototype = SpatialPrototype(store: StubPlacementStore())

        #expect(prototype.beginOpening())
        #expect(prototype.spaceState == .opening)
        #expect(prototype.isTransitioning)
        #expect(!prototype.beginOpening())
        #expect(!prototype.beginClosing())

        prototype.spaceDidAppear()
        #expect(prototype.spaceState == .open)
        #expect(!prototype.isTransitioning)
        #expect(!prototype.beginOpening())
        #expect(prototype.beginClosing())
        #expect(prototype.spaceState == .closing)
        #expect(!prototype.beginClosing())
        #expect(!prototype.beginOpening())
    }

    @Test func cancelledOpeningCanBeRetried() {
        let prototype = SpatialPrototype(store: StubPlacementStore())
        #expect(prototype.beginOpening())
        prototype.openingDidFail(message: nil)

        #expect(prototype.spaceState == .closed)
        #expect(!prototype.isTransitioning)
        #expect(prototype.message == nil)
        #expect(prototype.beginOpening())
    }

    @Test func failedOpeningReportsErrorAndRetryClearsIt() {
        let prototype = SpatialPrototype(store: StubPlacementStore())
        #expect(prototype.beginOpening())
        prototype.openingDidFail(message: "Opening failed")

        #expect(prototype.spaceState == .closed)
        #expect(prototype.message == "Opening failed")
        #expect(prototype.beginOpening())
        #expect(prototype.message == nil)
    }

    @Test func lateOpeningFailureDoesNotCloseVisibleSpace() {
        let prototype = SpatialPrototype(store: StubPlacementStore())
        #expect(prototype.beginOpening())
        prototype.spaceDidAppear()
        prototype.openingDidFail(message: "Late opening failure")

        #expect(prototype.spaceState == .open)
        #expect(prototype.message == nil)
        #expect(!prototype.isTransitioning)
    }

    @Test func disappearanceClearsActivityButRetainsAnchorAssociation() {
        let saved = SavedPlacement(anchorID: UUID())
        let store = StubPlacementStore(placement: saved)
        let prototype = SpatialPrototype(store: store)
        #expect(prototype.beginOpening())
        prototype.spaceDidAppear()
        #expect(prototype.beginClosing())
        prototype.spaceDidDisappear()

        #expect(prototype.spaceState == .closed)
        #expect(prototype.trackingState == .idle)
        #expect(!prototype.isBusy)
        #expect(!prototype.deviceIsTracked)
        #expect(!prototype.anchorIsTracked)
        #expect(!prototype.contentEntity.isEnabled)
        #expect(prototype.savedPlacement == saved)
        #expect(store.placement == saved)
        #expect(store.clearCount == 0)
    }

    @Test func forgettingRemovesAssociationAndClearsBusyState() async {
        let store = StubPlacementStore(placement: SavedPlacement(anchorID: UUID()))
        let prototype = SpatialPrototype(store: store)
        await prototype.forgetPlacement()

        #expect(prototype.savedPlacement == nil)
        #expect(!prototype.hasSavedPlacement)
        #expect(!prototype.storageNeedsReset)
        #expect(!prototype.restorationTimedOut)
        #expect(!prototype.isBusy)
        #expect(!prototype.anchorIsTracked)
        #expect(!prototype.contentEntity.isEnabled)
        #expect(prototype.message == nil)
        #expect(store.placement == nil)
        #expect(store.clearCount == 1)
    }

    @Test func forgettingAllowsRecoveryFromUnreadableStorage() async {
        let store = StubPlacementStore()
        store.failsLoad = true
        let prototype = SpatialPrototype(store: store)
        #expect(prototype.storageNeedsReset)
        await prototype.forgetPlacement()

        #expect(!prototype.storageNeedsReset)
        #expect(prototype.message == nil)
        #expect(!prototype.isBusy)
        #expect(store.clearCount == 1)
    }

    @Test func failedForgetPreservesOriginalAssociationAndReportsError() async {
        let saved = SavedPlacement(anchorID: UUID())
        let store = StubPlacementStore(placement: saved)
        store.failsClear = true
        let prototype = SpatialPrototype(store: store)
        await prototype.forgetPlacement()

        #expect(prototype.savedPlacement == saved)
        #expect(prototype.hasSavedPlacement)
        #expect(store.placement == saved)
        #expect(prototype.message != nil)
        #expect(!prototype.isBusy)
        #expect(store.clearCount == 1)
    }

    @Test func failedResetKeepsUnreadableStorageFlag() async {
        let store = StubPlacementStore()
        store.failsLoad = true
        store.failsClear = true
        let prototype = SpatialPrototype(store: store)
        await prototype.forgetPlacement()

        #expect(prototype.storageNeedsReset)
        #expect(prototype.message != nil)
        #expect(!prototype.isBusy)
    }
}

@MainActor
private final class StubPlacementStore: PlacementPersisting {
    enum Failure: Error { case load, clear }

    var placement: SavedPlacement?
    var failsLoad = false
    var failsClear = false
    private(set) var loadCount = 0
    private(set) var saveCount = 0
    private(set) var clearCount = 0

    init(placement: SavedPlacement? = nil) {
        self.placement = placement
    }

    func load() throws -> SavedPlacement? {
        loadCount += 1
        if failsLoad { throw Failure.load }
        return placement
    }

    func save(_ placement: SavedPlacement) throws {
        saveCount += 1
        self.placement = placement
    }

    func clear() throws {
        clearCount += 1
        if failsClear { throw Failure.clear }
        placement = nil
    }
}
