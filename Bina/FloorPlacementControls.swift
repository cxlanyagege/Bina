import SwiftUI

struct FloorPlacementControls: View {
    let prototype: SpatialPrototype

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(prototype.floorPlacement.statusDescription)
                .font(.callout)
                .accessibilityIdentifier("placement.floorStatus")
            if let message = prototype.floorPlacement.message {
                Text(message).font(.callout).foregroundStyle(.orange)
            }
            if prototype.floorPlacement.preview != nil {
                Text("绿色圆盘标出鞋底落点与预留范围。确认前请查看是否位于真实地板上。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("确认放置并保存") { Task { await prototype.confirmFloorPlacement() } }
                        .disabled(!prototype.canConfirmFloor)
                        .accessibilityIdentifier("placement.confirmFloor")
                    Button("取消预览") { prototype.floorPlacement.cancelPreview() }
                        .disabled(prototype.isBusy)
                }
            }
            Button(prototype.floorPlacement.preview == nil ? "预览地板落点" : "重新预览") {
                prototype.prepareFloorPlacement()
            }
            .disabled(!prototype.canPreviewFloor)
            .accessibilityIdentifier("placement.previewFloor")
            if prototype.canRetryFloorDetection {
                Button("重试地面识别") { Task { await prototype.retryFloorDetection() } }
            }
            Text("先查看前方地板，再预览并确认。确认后位置会固定；地面识别结果的更新会用于下一次放置。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
