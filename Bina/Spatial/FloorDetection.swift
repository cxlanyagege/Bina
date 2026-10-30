import ARKit
import Foundation
import Metal
import OSLog
import simd

/// Adapts authorized ARKit planes into copied geometry for the placement model.
@MainActor
final class FloorDetection {
    private let placement: FloorPlacement
    private(set) var provider: PlaneDetectionProvider?
    private var token: UUID?
    private var task: Task<Void, Never>?
    private var lastRefresh: TimeInterval = 0
    private var reportedInvalidPlanes: Set<UUID> = []
    private let logger = Logger(subsystem: "Bina", category: "FloorDetection")

    init(placement: FloorPlacement) { self.placement = placement }

    func prepare(session: ARKitSession, token: UUID) async -> PlaneDetectionProvider? {
        stop()
        self.token = token
        placement.beginRun(token)
        guard PlaneDetectionProvider.isSupported else {
            placement.setAvailability(.unsupported, token: token)
            return nil
        }
        placement.setAvailability(.requestingAuthorization, token: token)
        let authorization = await session.requestAuthorization(for: PlaneDetectionProvider.requiredAuthorizations)
        guard self.token == token, !Task.isCancelled else { return nil }
        guard authorization[.worldSensing] == .allowed else {
            placement.setAvailability(.denied, token: token)
            return nil
        }
        let provider = PlaneDetectionProvider(alignments: [.horizontal])
        self.provider = provider
        placement.setAvailability(.starting, token: token)
        task = Task { [weak self] in
            for await update in provider.anchorUpdates {
                guard !Task.isCancelled, let self, self.token == token else { return }
                let now = ProcessInfo.processInfo.systemUptime
                switch update.event {
                case .added, .updated:
                    if let surface = self.snapshot(update.anchor) {
                        self.placement.receive(surface, token: token, now: now)
                    } else {
                        self.placement.remove(update.anchor.id, token: token, now: now)
                    }
                case .removed:
                    self.placement.remove(update.anchor.id, token: token, now: now)
                    self.reportedInvalidPlanes.remove(update.anchor.id)
                @unknown default: break
                }
            }
        }
        return provider
    }

    func startUnavailable(token: UUID) {
        stop()
        self.token = token
        placement.beginRun(token)
        placement.setAvailability(.failed, token: token)
    }

    func receiveState(providers: [any DataProvider], state: DataProviderState, error: ARKitSession.Error?, token: UUID)
    {
        guard self.token == token, let provider, providers.contains(where: { $0 === provider }),
            placement.availability != .denied
        else { return }
        if let error {
            logger.error("Plane detection failed: \(String(describing: error), privacy: .private)")
            placement.setAvailability(.failed, token: token)
            return
        }
        switch state {
        case .initialized: placement.setAvailability(.starting, token: token)
        case .running: placement.setAvailability(.running, token: token)
        case .paused: placement.setAvailability(.paused, token: token)
        case .stopped: placement.setAvailability(.failed, token: token)
        @unknown default: placement.setAvailability(.failed, token: token)
        }
    }

    func receiveAuthorization(
        type: ARKitSession.AuthorizationType, status: ARKitSession.AuthorizationStatus, token: UUID
    ) {
        guard self.token == token, type == .worldSensing else { return }
        if status != .allowed { placement.setAvailability(.denied, token: token) }
    }

    func setTrackingAvailable(_ available: Bool, token: UUID) {
        guard self.token == token else { return }
        let recovered = available && !placement.trackingAvailable
        placement.setTrackingAvailable(available, token: token)
        if recovered { lastRefresh = 0 }
    }

    func refresh(now: TimeInterval, token: UUID) {
        guard self.token == token, let provider, provider.state == .running,
            placement.availability == .running, placement.trackingAvailable,
            now - lastRefresh >= 0.5
        else { return }
        lastRefresh = now
        // Static planes need not emit another update after visibility recovery.
        let surfaces = provider.allAnchors.lazy.filter {
            $0.alignment == .horizontal && $0.surfaceClassification == .floor
        }
        .prefix(128).compactMap(snapshot)
        placement.reconcile(Array(surfaces), token: token, now: now)
    }

    func stop() {
        token = nil
        task?.cancel()
        task = nil
        provider = nil
        lastRefresh = 0
        reportedInvalidPlanes.removeAll()
        placement.endRun()
    }

    private func snapshot(_ anchor: PlaneAnchor) -> FloorSurface? {
        guard anchor.alignment == .horizontal, anchor.surfaceClassification == .floor else { return nil }
        let source = anchor.geometry.meshVertices
        let faces = anchor.geometry.meshFaces
        guard source.format == .float3, source.componentsPerVector == 3,
            source.buffer.storageMode == .shared, faces.buffer.storageMode == .shared,
            (3...8192).contains(source.count), (12...256).contains(source.stride), source.offset >= 0,
            source.offset <= source.buffer.length,
            (source.count - 1) * source.stride + 12 <= source.buffer.length - source.offset,
            faces.primitive == .triangle, (1...16384).contains(faces.count),
            [2, 4].contains(faces.bytesPerIndex), faces.count * 3 * faces.bytesPerIndex <= faces.buffer.length
        else {
            reportInvalid(anchor.id)
            return nil
        }
        let vertexBytes = source.buffer.contents()
        let vertices = (0..<source.count).map { i -> SIMD3<Float> in
            let offset = source.offset + i * source.stride
            return SIMD3(
                vertexBytes.loadUnaligned(fromByteOffset: offset, as: Float.self),
                vertexBytes.loadUnaligned(fromByteOffset: offset + 4, as: Float.self),
                vertexBytes.loadUnaligned(fromByteOffset: offset + 8, as: Float.self))
        }
        let indexBytes = faces.buffer.contents()
        let indices = (0..<(faces.count * 3)).map { i -> UInt32 in
            faces.bytesPerIndex == 2
                ? UInt32(indexBytes.loadUnaligned(fromByteOffset: i * 2, as: UInt16.self))
                : indexBytes.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self)
        }
        let surface = FloorSurface(
            id: anchor.id, classification: .floor, originFromAnchor: anchor.originFromAnchorTransform,
            vertices: vertices, triangleIndices: indices)
        if surface == nil { reportInvalid(anchor.id) }
        return surface
    }

    private func reportInvalid(_ id: UUID) {
        if reportedInvalidPlanes.insert(id).inserted {
            logger.error("Rejected an invalid or unsupported floor mesh: \(id, privacy: .private)")
        }
    }
}
