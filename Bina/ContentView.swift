import SwiftUI

struct ContentView: View {
    @Bindable var prototype: SpatialPrototype
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var showsForgetConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bina · 角色预览").font(.largeTitle)
                    Text("将角色放入房间，调整位置、尺寸和朝向。")
                        .foregroundStyle(.secondary)
                }
                GroupBox("角色模型") {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(prototype.characterDescription, systemImage: "person.crop.rectangle")
                        if prototype.characterState == .loading {
                            ProgressView()
                        }
                        if let message = prototype.characterMessage {
                            Text(message).font(.callout).foregroundStyle(.orange)
                        }
                        if prototype.characterState == .failed || prototype.characterState == .notLoaded {
                            Button("重新载入模型") {
                                Task { await prototype.loadCharacter() }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("空间状态") {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(prototype.trackingDescription, systemImage: "viewfinder")
                        Text(prototype.placementDescription)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button(prototype.spaceState == .closed ? "进入空间" : "退出空间") {
                                Task { await toggleSpace() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(prototype.isTransitioning)
                            if prototype.canRestartTracking {
                                Button("重试定位") {
                                    Task { await prototype.restartTracking() }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("下一次放置") {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("放置方式", selection: $prototype.placementMode) {
                            Text("站到地板").tag(SpatialPrototype.PlacementMode.floor)
                            Text("手动高度").tag(SpatialPrototype.PlacementMode.manualHeight)
                        }
                        .pickerStyle(.segmented)
                        .disabled(prototype.isBusy)
                        valueSlider("与头显的水平距离", value: $prototype.placementDistance, range: 0.75...3, unit: "米")
                            .disabled(prototype.isBusy)
                        if prototype.placementMode == .floor {
                            FloorPlacementControls(prototype: prototype)
                        } else {
                            valueSlider("脚底低于头显", value: $prototype.feetBelowHead, range: 0...2, unit: "米")
                                .disabled(prototype.isBusy)
                            Text("面向空处，调整高度后放置。这是手动高度，可在未识别到地面时使用。")
                                .font(.caption).foregroundStyle(.secondary)
                            Button(prototype.hasSavedPlacement ? "重新放置并保存" : "放置并保存") {
                                Task { await prototype.placeInFront() }
                            }
                            .disabled(!prototype.canPlace)
                        }
                    }
                }
                GroupBox("角色外观") {
                    VStack(alignment: .leading, spacing: 14) {
                        valueSlider("身高", value: $prototype.characterHeight, range: 0.4...1.9, unit: "米")
                        valueSlider("朝向调整", value: $prototype.headingDegrees, range: -180...180, unit: "度", step: 5)
                    }
                }
                .disabled(prototype.isBusy)
                GroupBox("站姿与待机") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(prototype.idleDescription).font(.callout)
                        if let message = prototype.characterIdleMessage {
                            Text(message).font(.callout).foregroundStyle(.orange)
                        }
                        HStack {
                            Button(prototype.characterIdle?.mode == .paused ? "继续待机" : "暂停待机") {
                                prototype.toggleIdlePlayback()
                            }
                            .disabled(prototype.characterIdle == nil || prototype.characterIdle?.mode == .reference)
                            Button(prototype.characterIdle?.mode == .reference ? "恢复自然待机" : "还原参考姿势") {
                                prototype.toggleReferencePose()
                            }
                            .disabled(prototype.characterIdle == nil)
                        }
                        if let motion = prototype.characterIdle {
                            Toggle("看向我", isOn: Bindable(motion).isAttentionEnabled)
                                .accessibilityIdentifier("character.attention")
                            Toggle("头发物理", isOn: Bindable(motion).isHairPhysicsEnabled)
                                .disabled(!motion.isHairPhysicsAvailable)
                                .accessibilityIdentifier("character.hairPhysics")
                            Toggle("显示物理调试", isOn: Bindable(motion).showsPhysicsDebug)
                                .disabled(!motion.isHairPhysicsAvailable)
                            if let message = motion.hairPhysicsMessage {
                                Text(message).font(.callout).foregroundStyle(.orange)
                            }
                            if motion.isHairPhysicsAvailable {
                                Button("记录物理计算耗时") { motion.recordPhysicsTiming() }
                                if let timing = motion.physicsTimingDescription {
                                    Text(timing).font(.caption).foregroundStyle(.secondary)
                                }
                                Text("当前模拟部分发束。调试显示中，绿色为发束骨骼，橙色为碰撞范围。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text("她会轻轻转头看向你，走到身后或靠得太近时自然回正。暂停会冻结整个姿势，开关改动在继续后生效；参考姿势保留原始模型效果。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("面部与眼部状态") {
                    if let motion = prototype.characterIdle, let face = motion.face {
                        CharacterFaceControls(face: face, isPlaying: motion.mode == .playing)
                    } else {
                        Text(prototype.characterIdle?.faceMessage ?? "面部控制尚未就绪。")
                            .font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let message = prototype.message {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("spatialPrototype.message")
                }
                if prototype.hasSavedPlacement || prototype.storageNeedsReset {
                    Button("忘记保存的位置", role: .destructive) {
                        showsForgetConfirmation = true
                    }
                    .disabled(prototype.isBusy || prototype.isTransitioning)
                }
                Text("再次进入时会尝试恢复同一位置。暂时失去定位时，替身会隐藏；可回到原处等待，也可重新放置。外观与放置参数在本次应用运行期间保留。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
        }
        .frame(width: 540, height: 760)
        .task { await prototype.loadCharacter() }
        .confirmationDialog("忘记保存的位置？", isPresented: $showsForgetConfirmation, titleVisibility: .visible) {
            Button("忘记位置", role: .destructive) {
                Task { await prototype.forgetPlacement() }
            }
        } message: {
            Text("这只会清除空间原型的位置记录。之后需要重新放置替身。")
        }
    }

    private func valueSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        unit: String,
        step: Double = 0.05
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue, specifier: "%.2f") \(unit)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step).accessibilityLabel(title)
        }
    }

    private func toggleSpace() async {
        if prototype.spaceState == .closed {
            guard prototype.beginOpening() else { return }
            switch await openImmersiveSpace(id: SpatialPrototype.spaceID) {
            case .opened: break
            case .userCancelled: prototype.openingDidFail(message: nil)
            case .error: prototype.openingDidFail(message: "无法进入空间，请稍后重试。")
            @unknown default: prototype.openingDidFail(message: "空间未能打开，请重试。")
            }
        } else if prototype.beginClosing() {
            await dismissImmersiveSpace()
        }
    }
}
