import Foundation
import Testing
import simd

@testable import Bina

@MainActor
struct FloorPlacementTests {
    @Test func placementRequiresLiveTrackingAndStableClassifiedFloorEvidence() {
        let model = FloorPlacement()
        let token = UUID()
        #expect(!model.prepare(device: FloorTestGeometry.device(), settings: FloorTestGeometry.settings, now: 1))
        model.beginRun(token)
        model.setAvailability(.running, token: token)
        model.receive(FloorTestGeometry.rectangle(), token: token, now: 1)
        #expect(model.stableSurfaceCount == 0)
        model.setTrackingAvailable(true, token: token)
        let surface = FloorTestGeometry.rectangle()
        model.receive(surface, token: token, now: 1)
        #expect(!model.prepare(device: FloorTestGeometry.device(), settings: FloorTestGeometry.settings, now: 1.2))
        model.reconcile([surface], token: token, now: 1.5)
        #expect(model.stableSurfaceCount == 1)
        #expect(model.prepare(device: FloorTestGeometry.device(), settings: FloorTestGeometry.settings, now: 1.5))
    }

    @Test func floorHeightDoesNotDependOnSittingOrStandingHeadHeight() throws {
        let (model, token, surface) = ready()
        for height: Float in [0.7, 1.2, 1.9] {
            #expect(
                model.prepare(
                    device: FloorTestGeometry.device(height: height), settings: FloorTestGeometry.settings, now: 2))
            let preview = try #require(model.preview)
            #expect(abs(preview.transform.columns.3.y) < 0.00001)
            #expect(abs(preview.transform.columns.3.z + 2) < 0.00001)
            #expect(preview.planeID == surface.id)
            #expect(model.canConfirm(id: preview.id, settings: FloorTestGeometry.settings, now: 2))
        }
        model.remove(surface.id, token: token, now: 2)
        #expect(model.preview == nil)
    }

    @Test func tablesAndUnclassifiedPlanesDoNotReplaceTheFloor() throws {
        let (model, token, _) = ready()
        let surfaces = [
            FloorTestGeometry.rectangle(), FloorTestGeometry.rectangle(height: 0.8, kind: .other),
            FloorTestGeometry.rectangle(height: 1.0, kind: .unclassified),
        ]
        model.reconcile(surfaces, token: token, now: 2)
        model.reconcile(surfaces, token: token, now: 2.5)
        #expect(model.stableSurfaceCount == 1)
        #expect(model.prepare(device: FloorTestGeometry.device(), settings: FloorTestGeometry.settings, now: 3))
        #expect(try #require(model.preview).transform.columns.3.y == 0)
    }

    @Test func floorMayBeBelowTheTrackingWorldOrigin() throws {
        let (model, token, _) = ready()
        let surface = FloorTestGeometry.rectangle(height: -1.6)
        model.reconcile([surface], token: token, now: 2)
        model.reconcile([surface], token: token, now: 2.5)
        #expect(
            model.prepare(device: FloorTestGeometry.device(height: 0), settings: FloorTestGeometry.settings, now: 3))
        #expect(abs(try #require(model.preview).transform.columns.3.y + 1.6) < 0.00001)
    }

    @Test func targetOutsideFootprintOrAboveTheHeadRequiresAnotherPlacement() {
        let (model, token, _) = ready()
        for surface in [
            FloorTestGeometry.rectangle(halfWidth: 3, halfDepth: 2.05), FloorTestGeometry.rectangle(height: 2),
        ] {
            model.reconcile([surface], token: token, now: 2)
            model.reconcile([surface], token: token, now: 2.5)
            #expect(!model.prepare(device: FloorTestGeometry.device(), settings: FloorTestGeometry.settings, now: 3))
            #expect(model.preview == nil)
            #expect(model.message != nil)
        }
    }

    @Test func smallRefinementsKeepThePreviewFrozenAndLargeChangesInvalidateIt() throws {
        let (model, token, surface) = ready()
        #expect(model.prepare(device: FloorTestGeometry.device(), settings: FloorTestGeometry.settings, now: 2))
        let preview = try #require(model.preview)
        model.receive(FloorTestGeometry.rectangle(id: surface.id, height: 0.005), token: token, now: 2.1)
        #expect(model.preview?.id == preview.id)
        #expect(model.preview?.transform.columns.3.y == 0)
        #expect(model.canConfirm(id: preview.id, settings: preview.settings, now: 2.1))
        model.receive(FloorTestGeometry.rectangle(id: surface.id, height: 0.03), token: token, now: 2.2)
        #expect(model.preview == nil)
        #expect(model.message != nil)
        #expect(!model.canConfirm(id: preview.id, settings: preview.settings, now: 3))
    }

    @Test func cumulativeDriftCannotPassAsIndividuallySmallRefinements() {
        let (model, token, surface) = ready()
        #expect(model.prepare(device: FloorTestGeometry.device(), settings: FloorTestGeometry.settings, now: 2))
        for frame in 1...6 {
            model.receive(
                FloorTestGeometry.rectangle(id: surface.id, height: Float(frame) * 0.003), token: token,
                now: 2 + Double(frame) * 0.05)
        }
        #expect(model.stableSurfaceCount == 0)
        #expect(model.preview == nil)
    }

    @Test func planeFrameCorrectionsRequireAFreshPreviewEvenAtTheSameHeight() {
        for rotates in [false, true] {
            let (model, token, surface) = ready()
            #expect(model.prepare(device: FloorTestGeometry.device(), settings: FloorTestGeometry.settings, now: 2))
            var frame = matrix_identity_float4x4
            if rotates {
                frame = simd_float4x4(simd_quatf(angle: 0.1, axis: [0, 1, 0]))
            } else {
                frame.columns.3.x = 0.1
            }
            model.receive(FloorTestGeometry.rectangle(id: surface.id, frame: frame), token: token, now: 2.1)
            #expect(model.preview == nil)
            #expect(model.stableSurfaceCount == 0)
        }
    }

    @Test func shrinkingOrRemovingTheSupportingPlaneInvalidatesConfirmation() throws {
        let (model, token, surface) = ready()
        #expect(model.prepare(device: FloorTestGeometry.device(), settings: FloorTestGeometry.settings, now: 2))
        let preview = try #require(model.preview)
        model.receive(FloorTestGeometry.rectangle(id: surface.id, halfWidth: 0.1), token: token, now: 2.1)
        #expect(model.preview == nil)
        #expect(!model.canConfirm(id: preview.id, settings: preview.settings, now: 2.2))
        model.remove(surface.id, token: token, now: 2.2)
        #expect(model.stableSurfaceCount == 0)
    }

    @Test func trackingLossRequiresFreshEvidenceAfterRecovery() {
        let (model, token, surface) = ready()
        #expect(model.prepare(device: FloorTestGeometry.device(), settings: FloorTestGeometry.settings, now: 2))
        model.setTrackingAvailable(false, token: token)
        #expect(model.preview == nil)
        #expect(model.stableSurfaceCount == 0)
        model.setTrackingAvailable(true, token: token)
        #expect(!model.prepare(device: FloorTestGeometry.device(), settings: FloorTestGeometry.settings, now: 3))
        model.reconcile([surface], token: token, now: 3)
        #expect(!model.prepare(device: FloorTestGeometry.device(), settings: FloorTestGeometry.settings, now: 3.2))
        model.reconcile([surface], token: token, now: 3.5)
        #expect(model.prepare(device: FloorTestGeometry.device(), settings: FloorTestGeometry.settings, now: 3.5))
    }

    @Test func stoppedOrReplacedRunsRejectLatePlaneEventsAndAuthorizations() {
        let (model, old, surface) = ready()
        let token = UUID()
        model.beginRun(token)
        model.setTrackingAvailable(true, token: token)
        model.setAvailability(.running, token: old)
        model.receive(surface, token: old, now: 4)
        #expect(model.availability == .starting)
        #expect(model.stableSurfaceCount == 0)
        model.endRun()
        model.setAvailability(.running, token: token)
        model.reconcile([surface], token: token, now: 5)
        #expect(model.availability == .idle)
        #expect(model.preview == nil)
    }

    @Test func previewLeaseRejectsAppearanceChangesAndReplacementPreviews() throws {
        let (model, _, _) = ready()
        #expect(model.prepare(device: FloorTestGeometry.device(), settings: FloorTestGeometry.settings, now: 2))
        let preview = try #require(model.preview)
        let changed = FloorPlacementSettings(distance: 2, characterScale: 0.5, headingRadians: 0, contactRadius: 0.15)
        #expect(!model.canConfirm(id: preview.id, settings: changed, now: 2))
        #expect(model.prepare(device: FloorTestGeometry.device(), settings: FloorTestGeometry.settings, now: 2.1))
        #expect(!model.canConfirm(id: preview.id, settings: preview.settings, now: 2.1))
        model.finishPreview(id: preview.id)
        #expect(model.preview != nil)
        model.finishPreview(id: try #require(model.preview).id)
        #expect(model.preview == nil)
    }

    @Test func detectionFailuresClearOnlyTheUnconfirmedPreview() {
        for state: FloorPlacement.Availability in [.paused, .denied, .failed, .unsupported] {
            let (model, token, _) = ready()
            #expect(model.prepare(device: FloorTestGeometry.device(), settings: FloorTestGeometry.settings, now: 2))
            model.setAvailability(state, token: token)
            #expect(model.preview == nil)
            #expect(model.stableSurfaceCount == 0)
            #expect(!model.statusDescription.isEmpty)
        }
    }

    @Test func invalidSettingsCannotCreateOrConfirmAPlacement() {
        let (model, _, _) = ready()
        for settings in [
            FloorPlacementSettings(distance: .nan, characterScale: 1, headingRadians: 0, contactRadius: 0.15),
            FloorPlacementSettings(distance: 2, characterScale: -1, headingRadians: 0, contactRadius: 0.15),
            FloorPlacementSettings(distance: 2, characterScale: 1, headingRadians: .infinity, contactRadius: 0.15),
            FloorPlacementSettings(distance: 2, characterScale: 1, headingRadians: 0, contactRadius: 0),
        ] { #expect(!model.prepare(device: FloorTestGeometry.device(), settings: settings, now: 2)) }
    }

    private func ready() -> (FloorPlacement, UUID, FloorSurface) {
        let model = FloorPlacement()
        let token = UUID()
        let surface = FloorTestGeometry.rectangle()
        model.beginRun(token)
        model.setAvailability(.running, token: token)
        model.setTrackingAvailable(true, token: token)
        model.receive(surface, token: token, now: 1)
        model.reconcile([surface], token: token, now: 1.5)
        return (model, token, surface)
    }
}
