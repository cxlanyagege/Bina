import Foundation
import Observation
import simd

nonisolated struct FloorPlacementSettings: Equatable {
    let distance: Float
    let characterScale: Float
    let headingRadians: Float
    let contactRadius: Float

    var clearance: Float { contactRadius * characterScale + 0.03 }
    var isValid: Bool {
        distance.isFinite && (0.75...3).contains(distance)
            && characterScale.isFinite && (0.25...1.2).contains(characterScale)
            && headingRadians.isFinite && abs(headingRadians) <= .pi + 0.0001
            && contactRadius.isFinite && (0.025...0.5).contains(contactRadius)
    }
}

nonisolated struct FloorPlacementPreview {
    let id: UUID
    let planeID: UUID
    let transform: simd_float4x4
    let settings: FloorPlacementSettings
}

/// Keeps live floor evidence separate from a confirmed, independently anchored placement.
@MainActor
@Observable
final class FloorPlacement {
    enum Availability { case idle, requestingAuthorization, starting, running, paused, denied, unsupported, failed }
    private struct Entry {
        let surface: FloorSurface
        let reference: FloorSurface
        let stableSince: TimeInterval
    }

    private(set) var availability = Availability.idle
    private(set) var trackingAvailable = false
    private(set) var stableSurfaceCount = 0
    private(set) var preview: FloorPlacementPreview?
    private(set) var message: String?
    @ObservationIgnored private var token: UUID?
    @ObservationIgnored private var surfaces: [UUID: Entry] = [:]

    var statusDescription: String {
        switch availability {
        case .idle: return "进入空间后识别地面。"
        case .requestingAuthorization: return "正在请求地面识别所需的空间感知权限…"
        case .starting: return "正在启动地面识别…"
        case .running:
            if !trackingAvailable { return "等待头显定位恢复后继续识别地面。" }
            return stableSurfaceCount > 0 ? "已识别稳定地面，可以预览放置落点。" : "正在寻找地面，请缓慢查看前方地板。"
        case .paused: return "地面识别已暂停，恢复后请重新预览落点。"
        case .denied: return "空间感知权限未允许，可使用手动高度。允许权限后可重试地面识别。"
        case .unsupported: return "当前环境不支持地面识别，可使用手动高度；真实地面需要在 Vision Pro 上测试。"
        case .failed: return "地面识别暂不可用，仍可手动放置，或重试识别。"
        }
    }

    func beginRun(_ token: UUID) {
        self.token = token
        availability = .starting
        trackingAvailable = false
        clearEvidence()
        message = nil
    }

    func endRun() {
        token = nil
        availability = .idle
        trackingAvailable = false
        clearEvidence()
        message = nil
    }

    func setAvailability(_ value: Availability, token: UUID) {
        guard self.token == token else { return }
        availability = value
        if value != .running { clearEvidence() }
    }

    func setTrackingAvailable(_ value: Bool, token: UUID) {
        guard self.token == token, trackingAvailable != value else { return }
        trackingAvailable = value
        if !value { clearEvidence() }
    }

    func receive(_ surface: FloorSurface, token: UUID, now: TimeInterval) {
        guard self.token == token, availability == .running, trackingAvailable, now.isFinite else { return }
        if surface.isUsableFloor {
            let old = surfaces[surface.id]
            let stable = old.map { surface.isStable(comparedTo: $0.reference) } ?? false
            let since = stable ? old!.stableSince : now
            let reference = stable ? old!.reference : surface
            if surfaces[surface.id] != nil || surfaces.count < 128 {
                surfaces[surface.id] = Entry(surface: surface, reference: reference, stableSince: since)
            }
        } else {
            surfaces.removeValue(forKey: surface.id)
        }
        updateEvidence(now: now)
    }

    func remove(_ id: UUID, token: UUID, now: TimeInterval) {
        guard self.token == token else { return }
        surfaces.removeValue(forKey: id)
        updateEvidence(now: now)
    }

    func reconcile(_ snapshots: [FloorSurface], token: UUID, now: TimeInterval) {
        guard self.token == token, availability == .running, trackingAvailable else { return }
        let ids = Set(snapshots.map(\.id))
        surfaces = surfaces.filter { ids.contains($0.key) }
        for snapshot in snapshots { receive(snapshot, token: token, now: now) }
        updateEvidence(now: now)
    }

    @discardableResult
    func prepare(device: simd_float4x4, settings: FloorPlacementSettings, now: TimeInterval) -> Bool {
        preview = nil
        guard availability == .running, trackingAvailable, settings.isValid, now.isFinite,
            let facing = PlacementGeometry.transform(inFrontOf: device, distance: settings.distance, verticalOffset: 0)
        else {
            message = "请等待定位与地面识别可用，平视前方后重新预览。"
            return false
        }
        let xz = SIMD2(facing.columns.3.x, facing.columns.3.z)
        let candidates = surfaces.values.compactMap { entry -> (FloorSurface, Float)? in
            guard now - entry.stableSince >= 0.4, let height = entry.surface.height(at: xz),
                (0.25...3).contains(device.columns.3.y - height),
                entry.surface.contains(SIMD3(xz.x, height, xz.y), clearance: settings.clearance)
            else { return nil }
            return (entry.surface, height)
        }.sorted { a, b in a.1 == b.1 ? a.0.id.uuidString < b.0.id.uuidString : a.1 > b.1 }
        guard let (surface, height) = candidates.first else {
            message = "落点处还没有足够的稳定地面。请查看地板、调整距离或转向后重新预览，也可使用手动高度。"
            return false
        }
        var transform = facing
        transform.columns.3.y = height
        preview = FloorPlacementPreview(id: UUID(), planeID: surface.id, transform: transform, settings: settings)
        message = nil
        return true
    }

    func canConfirm(id: UUID, settings: FloorPlacementSettings, now: TimeInterval) -> Bool {
        guard let preview, preview.id == id, preview.settings == settings else { return false }
        return isValid(preview, now: now)
    }

    func cancelPreview(message: String? = nil) {
        preview = nil
        self.message = message
    }

    func finishPreview(id: UUID) {
        if preview?.id == id { cancelPreview() }
    }

    private func isValid(_ preview: FloorPlacementPreview, now: TimeInterval) -> Bool {
        guard availability == .running, trackingAvailable, now.isFinite,
            let entry = surfaces[preview.planeID], now - entry.stableSince >= 0.4
        else { return false }
        let p = preview.transform.columns.3
        guard let height = entry.surface.height(at: SIMD2(p.x, p.z)), abs(height - p.y) <= 0.015 else { return false }
        return entry.surface.contains(SIMD3(p.x, height, p.z), clearance: preview.settings.clearance)
    }

    private func updateEvidence(now: TimeInterval) {
        stableSurfaceCount = surfaces.values.filter { now - $0.stableSince >= 0.4 }.count
        if let preview, !isValid(preview, now: now) {
            cancelPreview(message: "地面检测结果已变化，请重新预览落点。")
        }
    }

    private func clearEvidence() {
        surfaces.removeAll()
        stableSurfaceCount = 0
        preview = nil
    }
}
