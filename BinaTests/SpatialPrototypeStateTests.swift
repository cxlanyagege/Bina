import Foundation
import ARKit
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

    @Test func unrelatedProviderStatesCannotStopWorldTracking() {
        let prototype = SpatialPrototype(store: StubPlacementStore())
        let world = StateTestProvider(), planes = StateTestProvider()
        prototype.receiveSessionProviderState([world], state: .running, error: nil, worldProvider: world)
        #expect(prototype.trackingState == .running)
        prototype.receiveSessionProviderState([planes], state: .stopped, error: nil, worldProvider: world)
        #expect(prototype.trackingState == .running)
        prototype.receiveSessionProviderState([world], state: .paused, error: nil, worldProvider: world)
        #expect(prototype.trackingState == .paused)
    }

    @Test func appearanceModeAndDistanceChangesInvalidateAnUnconfirmedFloorPreview() {
        let prototype = SpatialPrototype(store: StubPlacementStore())
        for change in 0..<4 {
            let token = UUID(), surface = FloorTestGeometry.rectangle()
            prototype.floorPlacement.beginRun(token)
            prototype.floorPlacement.setAvailability(.running, token: token)
            prototype.floorPlacement.setTrackingAvailable(true, token: token)
            prototype.floorPlacement.receive(surface, token: token, now: 1)
            prototype.floorPlacement.reconcile([surface], token: token, now: 2)
            #expect(prototype.floorPlacement.prepare(device: FloorTestGeometry.device(), settings: FloorTestGeometry.settings, now: 2))
            switch change {
            case 0: prototype.characterHeight = 1.2
            case 1: prototype.headingDegrees = 45
            case 2: prototype.placementDistance = 1.5
            default: prototype.placementMode = .manualHeight
            }
            #expect(prototype.floorPlacement.preview == nil)
        }
    }

    @Test func floorEvidenceAloneCannotAuthorizeSavingAndDisappearanceClearsIt() async {
        let saved = SavedPlacement(anchorID: UUID())
        let store = StubPlacementStore(placement: saved)
        let prototype = SpatialPrototype(store: store)
        let token = UUID(), surface = FloorTestGeometry.rectangle()
        prototype.floorPlacement.beginRun(token)
        prototype.floorPlacement.setAvailability(.running, token: token)
        prototype.floorPlacement.setTrackingAvailable(true, token: token)
        prototype.floorPlacement.receive(surface, token: token, now: 1)
        prototype.floorPlacement.reconcile([surface], token: token, now: 2)
        #expect(prototype.floorPlacement.prepare(device: FloorTestGeometry.device(), settings: FloorTestGeometry.settings, now: 2))
        #expect(!prototype.canConfirmFloor)
        await prototype.confirmFloorPlacement()
        #expect(store.saveCount == 0)
        #expect(store.placement == saved)
        prototype.spaceDidDisappear()
        #expect(prototype.floorPlacement.preview == nil)
        #expect(prototype.floorPlacement.availability == .idle)
        prototype.floorPlacement.receive(surface, token: token, now: 3)
        #expect(prototype.floorPlacement.stableSurfaceCount == 0)
    }
}

private final class StateTestProvider: DataProvider, @unchecked Sendable {
    nonisolated static var isSupported: Bool { true }
    nonisolated static var requiredAuthorizations: [ARKitSession.AuthorizationType] { [] }
    nonisolated var state: DataProviderState { .running }
    nonisolated var description: String { "Synthetic provider state" }
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
