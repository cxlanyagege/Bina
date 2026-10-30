import ARKit
import Foundation
import Observation
import OSLog
import QuartzCore
import RealityKit

@MainActor
@Observable
final class SpatialPrototype {
    static let spaceID = "BinaSpatialPrototype"

    enum SpaceState { case closed, opening, open, closing }
    enum TrackingState { case idle, starting, running, paused, unsupported, failed }
    enum CharacterState { case notLoaded, loading, loaded, failed }
    enum PlacementMode { case floor, manualHeight }

    private(set) var spaceState = SpaceState.closed
    private(set) var trackingState = TrackingState.idle
    private(set) var isBusy = false
    private(set) var storageNeedsReset = false
    private(set) var message: String?
    private(set) var savedPlacement: SavedPlacement?
    private(set) var deviceIsTracked = false
    private(set) var anchorIsTracked = false
    private(set) var restorationTimedOut = false
    private(set) var characterState = CharacterState.notLoaded
    private(set) var characterMessage: String?
    private(set) var characterIdle: CharacterIdleMotion?
    private(set) var characterIdleMessage: String?
    let floorPlacement = FloorPlacement()
    var placementMode = PlacementMode.floor { didSet { floorPlacement.cancelPreview() } }
    var placementDistance = 2.0 { didSet { floorPlacement.cancelPreview() } }
    var feetBelowHead = 1.4
    var characterHeight = 1.6 { didSet { updateAppearance(); floorPlacement.cancelPreview() } }
    var headingDegrees = 0.0 { didSet { updateAppearance(); floorPlacement.cancelPreview() } }

    @ObservationIgnored let contentEntity = Entity()
    @ObservationIgnored let floorMarker = FloorPlacementMarker()
    @ObservationIgnored private let character = Entity()
    @ObservationIgnored private lazy var floorDetection = FloorDetection(placement: floorPlacement)
    private var groundContact: CharacterGroundContact? = .placeholder
    @ObservationIgnored private let store: any PlacementPersisting
    @ObservationIgnored private let logger = Logger(subsystem: "Bina", category: "SpatialPrototype")
    @ObservationIgnored private var session: ARKitSession?
    @ObservationIgnored private var provider: WorldTrackingProvider?
    @ObservationIgnored private var generation: UUID?
    @ObservationIgnored private var anchors: [UUID: WorldAnchor] = [:]
    @ObservationIgnored private var pendingAnchorID: UUID?
    @ObservationIgnored private var isSceneActive = true
    @ObservationIgnored private var anchorTask: Task<Void, Never>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var deviceTask: Task<Void, Never>?
    @ObservationIgnored private var restorationTask: Task<Void, Never>?
    @ObservationIgnored private var cleanupTask: Task<Void, Never>?
    @ObservationIgnored private var obsoleteAnchorIDs: Set<UUID> = []
    @ObservationIgnored private var anchorRevision = 0
    @ObservationIgnored private var lastAnchorRefresh: TimeInterval = 0
    @ObservationIgnored private var characterLoadTask: Task<Void, Never>?
    @ObservationIgnored private var characterLoadToken: UUID?
    @ObservationIgnored private var motionUpdateToken: UUID?

    init(store: (any PlacementPersisting)? = nil) {
        self.store = store ?? FilePlacementStore()
        character.addChild(PlaceholderCharacter.make())
        contentEntity.addChild(character)
        contentEntity.isEnabled = false
        do {
            savedPlacement = try self.store.load()
        } catch {
            storageNeedsReset = true
            message = "无法读取保存的位置。原记录已保留；可选择忘记位置后重新放置。"
            logger.error("Loading placement failed: \(String(describing: error), privacy: .private)")
        }
    }

    var hasSavedPlacement: Bool { savedPlacement != nil }
    var isTransitioning: Bool { spaceState == .opening || spaceState == .closing }
    var canPlace: Bool {
        spaceState == .open && trackingState == .running && deviceIsTracked && isSceneActive
            && !isBusy && !storageNeedsReset
    }
    var canRestartTracking: Bool {
        spaceState == .open && trackingState == .failed && !isBusy
    }
    var canPreviewFloor: Bool {
        canPlace && placementMode == .floor && groundContact != nil
            && floorPlacement.availability == .running && floorPlacement.stableSurfaceCount > 0
    }
    var canConfirmFloor: Bool {
        guard canPlace, placementMode == .floor, let preview = floorPlacement.preview,
              let settings = floorSettings else { return false }
        return floorPlacement.canConfirm(id: preview.id, settings: settings, now: ProcessInfo.processInfo.systemUptime)
    }
    var canRetryFloorDetection: Bool {
        spaceState == .open && isSceneActive && !isBusy && !isTransitioning
            && [.denied,.failed].contains(floorPlacement.availability)
    }
    var canShowFloorPreview: Bool {
        spaceState == .open && isSceneActive && trackingState == .running && deviceIsTracked
            && floorPlacement.trackingAvailable
    }
    private var floorSettings: FloorPlacementSettings? {
        guard let groundContact else { return nil }
        return FloorPlacementSettings(distance: Float(placementDistance), characterScale: Float(characterHeight)/CharacterAsset.referenceHeight,
            headingRadians: Float(headingDegrees) * .pi / 180, contactRadius: groundContact.radius)
    }

    var characterDescription: String {
        switch characterState {
        case .notLoaded: return "哥伦比娅尚未载入，当前使用空间替身。"
        case .loading: return "正在载入哥伦比娅，当前使用空间替身…"
        case .loaded: return "哥伦比娅模型已载入。"
        case .failed: return "哥伦比娅模型载入失败，当前使用空间替身。"
        }
    }

    func loadCharacter() async {
        if let characterLoadTask {
            await characterLoadTask.value
            return
        }
        guard characterState != .loaded else { return }
        let token = UUID()
        characterLoadToken = token
        characterState = .loading
        characterMessage = nil
        // Asset lifetime belongs to the app model, independently of immersive tracking runs.
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.characterLoadToken == token { self.characterLoadTask = nil }
            }
            do {
                let model = try await CharacterAsset.load()
                let contact: CharacterGroundContact?
                let groundMessage: String?
                do {
                    contact = try CharacterGroundContact.measure(in: model)
                    groundMessage = nil
                } catch {
                    contact = nil
                    groundMessage = CharacterGroundContactError.invalidGeometry.errorDescription
                    self.logger.error("Measuring sole contact failed: \(String(describing: error), privacy: .private)")
                }
                let idle: CharacterIdleMotion?
                let idleMessage: String?
                do {
                    idle = try await CharacterAsset.loadIdleMotion(for: model)
                    idleMessage = nil
                } catch {
                    idle = nil
                    idleMessage = (error as? CharacterIdleError)?.errorDescription
                        ?? "无法读取站姿数据，当前保留静态模型。请检查角色资源后重新运行。"
                    self.logger.error("Preparing character idle failed: \(String(describing: error), privacy: .private)")
                }
                guard self.characterLoadToken == token else { return }
                self.floorPlacement.cancelPreview()
                self.groundContact = contact
                self.character.children.removeAll()
                self.character.addChild(model)
                self.updateAppearance()
                self.characterState = .loaded
                self.characterMessage = groundMessage
                self.characterIdle = idle
                self.characterIdleMessage = idleMessage
            } catch {
                guard self.characterLoadToken == token else { return }
                self.characterState = .failed
                self.characterMessage = (error as? CharacterAssetError)?.errorDescription
                    ?? "无法读取哥伦比娅模型，请重新载入或检查角色资源。"
                self.logger.error("Loading character failed: \(String(describing: error), privacy: .private)")
            }
        }
        characterLoadTask = task
        await task.value
    }

    var idleDescription: String {
        guard let characterIdle else { return "站姿与待机动作尚未就绪。" }
        switch characterIdle.mode {
        case .reference: return "参考姿势：原始模型姿势。"
        case .paused: return "待机已暂停，保持当前姿势。"
        case .playing:
            return contentEntity.isEnabled ? "自然站姿与轻微待机动作正在播放。" : "自然待机已就绪，角色显示后继续播放。"
        }
    }

    func toggleIdlePlayback() {
        guard let characterIdle else { return }
        if characterIdle.mode == .playing { characterIdle.pause() }
        else if characterIdle.mode == .paused { characterIdle.resume() }
    }

    func toggleReferencePose() {
        guard let characterIdle else { return }
        if characterIdle.mode == .reference { characterIdle.showNatural() }
        else { characterIdle.showReference() }
    }

    func beginMotionUpdates() -> UUID {
        let token = UUID()
        motionUpdateToken = token
        return token
    }

    func endMotionUpdates(token: UUID?) {
        if motionUpdateToken == token {
            motionUpdateToken = nil
            characterIdle?.invalidateAttentionTarget()
        }
    }

    func advanceCharacterMotion(by deltaTime: TimeInterval, token: UUID) {
        guard motionUpdateToken == token else { return }
        let isVisible = spaceState == .open && isSceneActive && contentEntity.isEnabled
        var target: SIMD3<Float>?
        if isVisible, characterIdle?.isAttentionEnabled == true, characterIdle?.mode == .playing,
           trackingState == .running, let provider, provider.state == .running,
           let device = provider.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()), device.isTracked {
            let position = device.originFromAnchorTransform.columns.3
            target = SIMD3(position.x, position.y, position.z)
        }
        characterIdle?.advance(by: deltaTime, isVisible: isVisible, attentionTarget: target)
    }

    var trackingDescription: String {
        guard spaceState != .closed else { return "空间未打开" }
        switch trackingState {
        case .idle, .starting: return "正在启动空间定位…"
        case .running: return deviceIsTracked ? "空间定位可用" : "正在恢复头显定位…"
        case .paused: return "定位已暂停，等待恢复…"
        case .unsupported: return "当前运行环境不支持世界追踪，请在 Vision Pro 上测试。"
        case .failed: return "定位已停止，请重试定位或重新进入空间。"
        }
    }

    var placementDescription: String {
        if storageNeedsReset { return "位置记录需要处理，尚未覆盖原文件。" }
        guard savedPlacement != nil else { return "尚未保存位置。进入空间后可在面前放置替身。" }
        if spaceState == .closed { return "已有保存的位置，下次进入时会尝试恢复。" }
        if isBusy { return "正在更新位置…" }
        if anchorIsTracked { return "已找到保存的位置。定位可用时显示替身。" }
        if restorationTimedOut { return "暂时找不到保存的位置。可回到原房间等待，或重新放置。" }
        return "正在寻找保存的位置…"
    }

    func beginOpening() -> Bool {
        guard spaceState == .closed else { return false }
        spaceState = .opening
        if !storageNeedsReset { message = nil }
        return true
    }

    func openingDidFail(message: String?) {
        guard spaceState == .opening else { return }
        spaceState = .closed
        if let message { self.message = message }
    }

    func beginClosing() -> Bool {
        guard spaceState == .open else { return false }
        spaceState = .closing
        updateVisibility()
        return true
    }

    func spaceDidAppear() { spaceState = .open }

    func spaceDidDisappear() {
        motionUpdateToken = nil
        stopTracking()
        spaceState = .closed
    }

    func setSceneActive(_ active: Bool) {
        isSceneActive = active
        if !active {
            deviceIsTracked = false
            invalidateAnchors()
        }
        updateVisibility()
    }

    func startTracking() async {
        await startTracking(includeFloorDetection: true)
    }

    private func startTracking(includeFloorDetection: Bool) async {
        guard spaceState == .open, session == nil else { return }
        guard WorldTrackingProvider.isSupported else {
            trackingState = .unsupported
            let token = UUID()
            floorPlacement.beginRun(token)
            floorPlacement.setAvailability(.unsupported, token: token)
            return
        }

        // Stopped ARKit providers cannot be reused when the immersive space opens again.
        let session = ARKitSession()
        let provider = WorldTrackingProvider()
        let token = UUID()
        self.session = session
        self.provider = provider
        generation = token
        trackingState = .starting
        restorationTimedOut = false

        anchorTask = Task { [weak self] in
            for await update in provider.anchorUpdates {
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.receive(update)
            }
        }
        eventTask = Task { [weak self] in
            for await event in session.events {
                guard !Task.isCancelled, let self, self.generation == token else { return }
                switch event {
                case let .dataProviderStateChanged(providers, state, error):
                    self.receiveSessionProviderState(providers, state: state, error: error, worldProvider: provider)
                case let .authorizationChanged(type, status):
                    self.floorDetection.receiveAuthorization(type: type, status: status, token: token)
                @unknown default: break
                }
            }
        }

        let planes: PlaneDetectionProvider?
        if includeFloorDetection { planes = await floorDetection.prepare(session: session, token: token) }
        else { floorDetection.startUnavailable(token: token); planes = nil }
        guard generation == token, !Task.isCancelled else { return }
        do {
            var providers: [any DataProvider] = [provider]
            if let planes { providers.append(planes) }
            try await session.run(providers)
            guard generation == token, !Task.isCancelled else { return }
            receiveProviderState(provider.state, error: nil)
            if let planes { floorDetection.receiveState(providers: [planes], state: planes.state, error: nil, token: token) }
            startDeviceUpdates(provider: provider, token: token)
            startRestorationWait(token: token)
        } catch {
            guard generation == token else { return }
            if planes != nil, includeFloorDetection {
                logger.error("Combined floor/world tracking failed; retrying world tracking alone: \(String(describing: error), privacy: .private)")
                stopTracking()
                await startTracking(includeFloorDetection: false)
                return
            }
            trackingState = .failed
            message = "无法启动定位，请重试定位或退出后重新进入空间。"
            logger.error("Starting ARKit failed: \(String(describing: error), privacy: .private)")
            updateVisibility()
        }
    }

    func restartTracking() async {
        guard canRestartTracking else { return }
        stopTracking()
        if !storageNeedsReset { message = nil }
        await startTracking()
    }

    func retryFloorDetection() async {
        guard canRetryFloorDetection else { return }
        stopTracking()
        await startTracking()
    }

    func prepareFloorPlacement() {
        guard canPreviewFloor, let settings = floorSettings, let device = currentDeviceTransform() else { return }
        floorPlacement.prepare(device: device, settings: settings, now: ProcessInfo.processInfo.systemUptime)
    }

    func confirmFloorPlacement() async {
        guard canConfirmFloor, let preview = floorPlacement.preview, currentDeviceTransform() != nil else { return }
        await commitPlacement(transform: preview.transform, floorPreview: preview)
    }

    func placeInFront() async {
        guard canPlace, let device = currentDeviceTransform() else { return }
        guard let transform = PlacementGeometry.transform(
            inFrontOf: device,
            distance: Float(placementDistance),
            verticalOffset: -Float(feetBelowHead)
        ) else {
            message = "请平视前方后重试放置。"
            return
        }
        floorPlacement.cancelPreview()
        await commitPlacement(transform: transform, floorPreview: nil)
    }

    private func currentDeviceTransform() -> simd_float4x4? {
        guard let provider, provider.state == .running,
              let device = provider.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()), device.isTracked else {
            deviceIsTracked = false
            invalidateAnchors()
            updateVisibility()
            message = "头显定位已变化，请等待定位恢复后重试。"
            return nil
        }
        return device.originFromAnchorTransform
    }

    private func commitPlacement(transform: simd_float4x4, floorPreview: FloorPlacementPreview?) async {
        guard canPlace, let provider, let token = generation else { return }
        isBusy = true
        message = nil
        let anchor = WorldAnchor(originFromAnchorTransform: transform)
        pendingAnchorID = anchor.id
        defer {
            if generation == token {
                pendingAnchorID = nil
                isBusy = false
            }
        }

        do {
            try await provider.addAnchor(anchor)
        } catch {
            guard generation == token else { return }
            message = "无法建立新位置，原位置保持不变。请恢复定位后重试。"
            logger.error("Adding anchor failed: \(String(describing: error), privacy: .private)")
            anchors.removeValue(forKey: anchor.id)
            return
        }
        let worldIsValid = generation == token && canCommitPlacement && currentDeviceTransform() != nil
        let floorIsValid = floorPreview.map { preview in
            placementMode == .floor && floorSettings.map {
                floorPlacement.canConfirm(id: preview.id, settings: $0, now: ProcessInfo.processInfo.systemUptime)
            } == true
        } ?? true
        guard worldIsValid, floorIsValid else {
            if generation == token, floorPreview != nil {
                floorPlacement.cancelPreview(message: "预览已失效，原位置保持不变。请恢复定位后重新预览。")
            }
            anchors.removeValue(forKey: anchor.id)
            _ = await removeAnchor(anchor.id, from: provider)
            return
        }

        let previous = savedPlacement
        let replacement = SavedPlacement(anchorID: anchor.id, alignment: floorPreview == nil ? nil : .soleContact)
        do {
            try store.save(replacement)
        } catch {
            message = "无法保存新位置，原位置保持不变。请检查可用存储空间后重试。"
            logger.error("Saving placement failed: \(String(describing: error), privacy: .private)")
            _ = await removeAnchor(anchor.id, from: provider)
            if generation == token { anchors.removeValue(forKey: anchor.id) }
            return
        }

        // Commit the association before removing the old anchor; late updates cannot select it again.
        savedPlacement = replacement
        updateAppearance()
        if let floorPreview { floorPlacement.finishPreview(id: floorPreview.id) }
        anchors = anchors.filter { $0.key == anchor.id }
        restorationTimedOut = false
        updateAnchor()
        startRestorationWait(token: token)
        if let previous, previous.anchorID != anchor.id {
            let removed = await removeAnchor(previous.anchorID, from: provider)
            if !removed, generation == token { showCleanupWarning() }
        }
    }

    func forgetPlacement() async {
        guard !isBusy, !isTransitioning else { return }
        isBusy = true
        let token = generation
        defer { if generation == token { isBusy = false } }
        do {
            try store.clear()
        } catch {
            message = "无法清除位置记录，请稍后重试。"
            logger.error("Clearing placement failed: \(String(describing: error), privacy: .private)")
            return
        }
        let previous = savedPlacement
        savedPlacement = nil
        floorPlacement.cancelPreview()
        updateAppearance()
        storageNeedsReset = false
        restorationTimedOut = false
        restorationTask?.cancel()
        anchors.removeAll()
        message = nil
        updateAnchor()
        if let previous, let provider {
            let removed = await removeAnchor(previous.anchorID, from: provider)
            if !removed, generation == token { showCleanupWarning() }
        }
    }

    private func stopTracking() {
        generation = nil
        floorDetection.stop()
        anchorTask?.cancel()
        eventTask?.cancel()
        deviceTask?.cancel()
        restorationTask?.cancel()
        cleanupTask?.cancel()
        cleanupTask = nil
        obsoleteAnchorIDs.removeAll()
        session?.stop()
        session = nil
        provider = nil
        anchors.removeAll()
        pendingAnchorID = nil
        deviceIsTracked = false
        anchorIsTracked = false
        isBusy = false
        trackingState = .idle
        lastAnchorRefresh = 0
        contentEntity.isEnabled = false
        characterIdle?.invalidateAttentionTarget()
    }

    private func receive(_ update: AnchorUpdate<WorldAnchor>) {
        let id = update.anchor.id
        anchorRevision &+= 1
        guard id == savedPlacement?.anchorID || id == pendingAnchorID else {
            if update.event == .added, let provider, let token = generation {
                enqueueCleanup([id], provider: provider, token: token)
            }
            return
        }
        switch update.event {
        case .added, .updated:
            if isSceneActive && trackingState == .running && deviceIsTracked {
                anchors[id] = update.anchor
            }
        case .removed:
            anchors.removeValue(forKey: id)
            if id == savedPlacement?.anchorID { restorationTimedOut = true }
        }
        updateAnchor()
    }

    /// A floor-provider failure must not disable an otherwise valid world-tracking run.
    func receiveSessionProviderState(_ providers: [any DataProvider], state: DataProviderState,
                                     error: ARKitSession.Error?, worldProvider: any DataProvider) {
        if providers.contains(where: { $0 === worldProvider }) { receiveProviderState(state, error: error) }
        if let token = generation { floorDetection.receiveState(providers: providers, state: state, error: error, token: token) }
    }

    private func receiveProviderState(_ state: DataProviderState, error: ARKitSession.Error?) {
        switch state {
        case .initialized: trackingState = .starting
        case .running: trackingState = .running
        case .paused: trackingState = .paused
        case .stopped: trackingState = .failed
        @unknown default: trackingState = .failed
        }
        if let error {
            trackingState = .failed
            message = "空间定位遇到问题，请重试定位。保存的位置仍然保留。"
            logger.error("ARKit provider failed: \(String(describing: error), privacy: .private)")
        }
        if trackingState != .running {
            deviceIsTracked = false
            invalidateAnchors()
        }
        updateVisibility()
    }

    private func startDeviceUpdates(provider: WorldTrackingProvider, token: UUID) {
        deviceTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.generation == token else { return }
                let wasTracked = self.deviceIsTracked
                self.deviceIsTracked = self.isSceneActive && self.trackingState == .running
                    && provider.queryDeviceAnchor(atTimestamp: CACurrentMediaTime())?.isTracked == true
                if wasTracked && !self.deviceIsTracked { self.invalidateAnchors() }
                let now = CACurrentMediaTime()
                if self.deviceIsTracked, (!wasTracked || (self.hasSavedPlacement && !self.anchorIsTracked)),
                   now - self.lastAnchorRefresh >= 0.5 {
                    self.lastAnchorRefresh = now
                    await self.refreshAnchors(provider: provider, token: token)
                }
                self.updateVisibility()
                self.floorDetection.refresh(now: now, token: token)
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
        }
    }

    private func startRestorationWait(token: UUID) {
        restorationTask?.cancel()
        guard let id = savedPlacement?.anchorID, !anchorIsTracked else { return }
        restorationTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            guard let self, self.generation == token, self.savedPlacement?.anchorID == id,
                  !self.anchorIsTracked else { return }
            self.restorationTimedOut = true
        }
    }

    private func updateAnchor() {
        let anchor = savedPlacement.flatMap { anchors[$0.anchorID] }
        anchorIsTracked = anchor?.isTracked == true && isSceneActive
            && trackingState == .running && deviceIsTracked
        if let anchor, anchorIsTracked {
            contentEntity.transform = Transform(matrix: anchor.originFromAnchorTransform)
            restorationTimedOut = false
        }
        updateVisibility()
    }

    private var canCommitPlacement: Bool {
        spaceState == .open && isSceneActive && trackingState == .running && deviceIsTracked
    }

    private func invalidateAnchors() {
        anchorRevision &+= 1
        anchors.removeAll()
        anchorIsTracked = false
        lastAnchorRefresh = 0
        contentEntity.isEnabled = false
    }

    private func refreshAnchors(provider: WorldTrackingProvider, token: UUID) async {
        let revision = anchorRevision
        let existing = await provider.allAnchors ?? []
        guard generation == token, canCommitPlacement else { return }
        enqueueCleanup(existing.map(\.id), provider: provider, token: token)
        // A newer update or interruption takes precedence over a suspended snapshot read.
        guard revision == anchorRevision else { return }
        anchors = Dictionary(uniqueKeysWithValues: existing
            .filter { $0.id == savedPlacement?.anchorID || $0.id == pendingAnchorID }
            .map { ($0.id, $0) })
        updateAnchor()
    }

    private func enqueueCleanup(_ ids: [UUID], provider: WorldTrackingProvider, token: UUID) {
        // This prototype exclusively owns one placement; future anchor owners must refine this policy.
        guard !storageNeedsReset else { return }
        obsoleteAnchorIDs.formUnion(ids.filter { $0 != savedPlacement?.anchorID && $0 != pendingAnchorID })
        guard cleanupTask == nil, !obsoleteAnchorIDs.isEmpty else { return }
        cleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.generation == token else { return }
                guard let id = self.obsoleteAnchorIDs.popFirst() else {
                    self.cleanupTask = nil
                    return
                }
                guard id != self.savedPlacement?.anchorID, id != self.pendingAnchorID else { continue }
                let removed = await self.removeAnchor(id, from: provider)
                guard self.generation == token else { return }
                if !removed { self.showCleanupWarning() }
            }
        }
    }

    private func updateVisibility() {
        contentEntity.isEnabled = spaceState == .open && isSceneActive
            && trackingState == .running && deviceIsTracked && anchorIsTracked
        if !contentEntity.isEnabled { characterIdle?.invalidateAttentionTarget() }
        if let token = generation {
            floorDetection.setTrackingAvailable(spaceState == .open && isSceneActive
                && trackingState == .running && deviceIsTracked, token: token)
        }
    }

    private func updateAppearance() {
        guard characterHeight.isFinite, headingDegrees.isFinite else { return }
        character.scale = SIMD3(repeating: Float(characterHeight) / CharacterAsset.referenceHeight)
        character.orientation = simd_quatf(angle: Float(headingDegrees * .pi / 180), axis: [0, 1, 0])
        if savedPlacement?.alignment == .soleContact, let groundContact {
            character.position = groundContact.correction(scale: Float(characterHeight)/CharacterAsset.referenceHeight,
                                                         heading: Float(headingDegrees * .pi/180))
        } else { character.position = .zero }
    }

    private func removeAnchor(_ id: UUID, from provider: WorldTrackingProvider) async -> Bool {
        do {
            try await provider.removeAnchor(forID: id)
            return true
        } catch {
            logger.error("Removing unused anchor failed: \(String(describing: error), privacy: .private)")
            return false
        }
    }

    private func showCleanupWarning() {
        message = "位置记录已更新，但旧空间锚点未能清理。可重新进入空间后继续测试。"
    }
}
