import XCTest
import simd
@testable import Bina

@MainActor
final class PlacementGeometryTests: XCTestCase {
    func testIdentityDevicePlacesCharacterAheadAndFacingUser() throws {
        let transform = try XCTUnwrap(PlacementGeometry.transform(
            inFrontOf: matrix_identity_float4x4,
            distance: 2,
            verticalOffset: -1.4
        ))

        assertVector(transform.columns.3, equals: SIMD4<Float>(0, -1.4, -2, 1))
        assertVector(transform.columns.1, equals: SIMD4<Float>(0, 1, 0, 0))
        assertVector(-transform.columns.2, equals: SIMD4<Float>(0, 0, 1, 0))
        XCTAssertEqual(simd_determinant(transform), 1, accuracy: 0.0001)
    }

    func testYawChangesPlacementAndCharacterFacingDirection() throws {
        let device = simd_float4x4(simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 1, 0)))
        let transform = try XCTUnwrap(PlacementGeometry.transform(
            inFrontOf: device,
            distance: 2,
            verticalOffset: -1
        ))

        assertVector(transform.columns.3, equals: SIMD4<Float>(-2, -1, 0, 1))
        assertVector(-transform.columns.2, equals: SIMD4<Float>(1, 0, 0, 0))
        assertVector(transform.columns.1, equals: SIMD4<Float>(0, 1, 0, 0))
    }

    func testHeadPitchDoesNotTiltCharacterOrChangeHorizontalDistance() throws {
        let device = simd_float4x4(simd_quatf(angle: .pi / 3, axis: SIMD3<Float>(1, 0, 0)))
        let transform = try XCTUnwrap(PlacementGeometry.transform(
            inFrontOf: device,
            distance: 2,
            verticalOffset: -1.4
        ))

        assertVector(transform.columns.3, equals: SIMD4<Float>(0, -1.4, -2, 1))
        assertVector(transform.columns.1, equals: SIMD4<Float>(0, 1, 0, 0))
        assertVector(-transform.columns.2, equals: SIMD4<Float>(0, 0, 1, 0))
    }

    func testDeviceTranslationAndManualHeightOffsetArePreserved() throws {
        var device = matrix_identity_float4x4
        device.columns.3 = SIMD4<Float>(3, 1.7, 4, 1)
        let transform = try XCTUnwrap(PlacementGeometry.transform(
            inFrontOf: device,
            distance: 1.5,
            verticalOffset: -1.2
        ))

        assertVector(transform.columns.3, equals: SIMD4<Float>(3, 0.5, 2.5, 1))
    }

    func testVerticalHeadDirectionRequiresUsableHorizontalHeading() {
        let device = simd_float4x4(simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0)))

        XCTAssertNil(PlacementGeometry.transform(inFrontOf: device, distance: 2, verticalOffset: -1))
    }

    func testInvalidParametersDoNotProducePlacement() {
        let invalidDistances: [Float] = [0, -1, .nan, .infinity]
        for distance in invalidDistances {
            XCTAssertNil(PlacementGeometry.transform(
                inFrontOf: matrix_identity_float4x4,
                distance: distance,
                verticalOffset: -1
            ))
        }
        let invalidOffsets: [Float] = [.nan, .infinity, -.infinity]
        for offset in invalidOffsets {
            XCTAssertNil(PlacementGeometry.transform(
                inFrontOf: matrix_identity_float4x4,
                distance: 2,
                verticalOffset: offset
            ))
        }
    }

    func testNonfiniteDeviceMatrixDoesNotProducePlacement() {
        var device = matrix_identity_float4x4
        device.columns.0.x = .nan

        XCTAssertNil(PlacementGeometry.transform(inFrontOf: device, distance: 2, verticalOffset: -1))

        device = matrix_identity_float4x4
        device.columns.3.z = .infinity
        XCTAssertNil(PlacementGeometry.transform(inFrontOf: device, distance: 2, verticalOffset: -1))
    }

    func testOverflowingPositionDoesNotProducePlacement() {
        var device = matrix_identity_float4x4
        device.columns.3.z = -Float.greatestFiniteMagnitude

        XCTAssertNil(PlacementGeometry.transform(
            inFrontOf: device,
            distance: .greatestFiniteMagnitude,
            verticalOffset: 0
        ))
    }

    private func assertVector(
        _ actual: SIMD4<Float>,
        equals expected: SIMD4<Float>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for index in 0..<4 {
            XCTAssertEqual(actual[index], expected[index], accuracy: 0.0001, file: file, line: line)
        }
    }
}
