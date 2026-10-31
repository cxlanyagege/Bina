#!/usr/bin/env swift
import CoreGraphics
import Foundation
import ImageIO

enum IconCheckError: Error, CustomStringConvertible {
    case invalid(String)

    var description: String {
        switch self {
        case .invalid(let message): message
        }
    }
}

func checkForeground(at url: URL) throws {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw IconCheckError.invalid("Cannot read the icon foreground at \(url.path).")
    }
    let side = 1024
    guard image.width == side, image.height == side else {
        throw IconCheckError.invalid("The icon foreground must be 1024 by 1024 pixels.")
    }
    guard let context = CGContext(data: nil, width: side, height: side,
                                  bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let data = context.data else {
        throw IconCheckError.invalid("Cannot decode the icon foreground alpha channel.")
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    let rgba = data.assumingMemoryBound(to: UInt8.self)
    let alpha = (0..<(side * side)).map { rgba[$0 * 4 + 3] }
    var visited = [Bool](repeating: false, count: alpha.count)
    var areas: [Int] = []

    // Even barely visible alpha islands participate in the system's depth effects.
    // Eight-way connectivity keeps diagonal antialiased feather edges attached.
    for origin in alpha.indices where alpha[origin] != 0 && !visited[origin] {
        var queue = [origin]
        var cursor = 0
        visited[origin] = true
        while cursor < queue.count {
            let point = queue[cursor]
            cursor += 1
            let x = point % side
            let y = point / side
            for dy in -1...1 {
                for dx in -1...1 where dx != 0 || dy != 0 {
                    let nx = x + dx
                    let ny = y + dy
                    guard (0..<side).contains(nx), (0..<side).contains(ny) else { continue }
                    let next = ny * side + nx
                    if alpha[next] != 0 && !visited[next] {
                        visited[next] = true
                        queue.append(next)
                    }
                }
            }
        }
        areas.append(queue.count)
    }
    guard !areas.isEmpty else {
        throw IconCheckError.invalid("The icon foreground is empty.")
    }
    guard alpha.contains(0) else {
        throw IconCheckError.invalid("The icon foreground has no transparent background.")
    }
    // This ornament is one connected shape, including its clasp and feather tails.
    guard areas.count == 1 else {
        let strayPixels = areas.reduce(0, +) - areas.max()!
        throw IconCheckError.invalid("Found \(areas.count - 1) disconnected alpha regions containing \(strayPixels) stray pixels.")
    }
    for index in alpha.indices where alpha[index] >= 64 {
        let dx = Double(index % side) + 0.5 - Double(side) / 2
        let dy = Double(index / side) + 0.5 - Double(side) / 2
        guard dx * dx + dy * dy <= pow(Double(side) * 0.45, 2) else {
            throw IconCheckError.invalid("The icon foreground exceeds its circular safe margin.")
        }
    }
    print("PASS: 1024 x 1024; one connected foreground; zero isolated alpha pixels; circular safe margin preserved.")
}

let defaultPath = "Bina/Assets.xcassets/AppIcon.solidimagestack/Front.solidimagestacklayer/Content.imageset/Headpiece.png"
guard CommandLine.arguments.count <= 2 else {
    FileHandle.standardError.write(Data("Usage: swift scripts/check-app-icon-alpha.swift [foreground.png]\n".utf8))
    exit(2)
}
do {
    try checkForeground(at: URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? defaultPath))
} catch {
    FileHandle.standardError.write(Data("App icon alpha check failed: \(error)\n".utf8))
    exit(1)
}
