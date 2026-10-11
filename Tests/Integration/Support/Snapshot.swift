import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private final class Marker {}

/// Compares rendered images with reference PNGs in `Tests/Integration/Snapshots/` (spec §14.1).
///
/// Run the tests with `TEST_RUNNER_LSO_RECORD_SNAPSHOTS=1` to write new references instead of
/// comparing; each test then fails, so a recording is never mistaken for a pass.
enum Snapshot {
    /// How far one channel of a pixel may be from the reference.
    static let channelTolerance = 2
    /// The share of pixels that may differ by more than that.
    static let pixelTolerance = 0.001

    /// `nil` if `image` matches the reference `name`, otherwise why it doesn't.
    static func mismatch(_ image: CGImage, _ name: String) -> String? {
        if ProcessInfo.processInfo.environment["LSO_RECORD_SNAPSHOTS"] == "1" {
            // This file is Tests/Integration/Support/Snapshot.swift.
            let folder = URL(filePath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().appending(path: "Snapshots")
            let url = folder.appending(path: "\(name).png")
            return write(image, to: url)
                ? "Recorded \(url.path). Run again without recording to compare."
                : "Couldn't record \(url.path)."
        }
        guard let url = Bundle(for: Marker.self).url(forResource: name, withExtension: "png"),
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let reference = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return "No reference \(name).png. Record it (see CONTRIBUTING.md)." }
        guard reference.width == image.width, reference.height == image.height else {
            return "\(name): \(image.width)×\(image.height), reference "
                + "\(reference.width)×\(reference.height). \(saveActual(image, name))"
        }
        guard let actual = pixels(of: image), let expected = pixels(of: reference) else {
            return "\(name): couldn't read the pixels. \(saveActual(image, name))"
        }
        var differing = 0
        for pixel in stride(from: 0, to: actual.count, by: 4) {
            for channel in pixel..<pixel + 4
            where abs(Int(actual[channel]) - Int(expected[channel])) > channelTolerance {
                differing += 1
                break
            }
        }
        let share = Double(differing) / Double(image.width * image.height)
        guard share > pixelTolerance else { return nil }
        return "\(name): \(differing) pixels differ. \(saveActual(image, name))"
    }

    /// Saves this run's image to the temporary folder, and says where.
    private static func saveActual(_ image: CGImage, _ name: String) -> String {
        let saved = FileManager.default.temporaryDirectory
            .appending(path: "lso-snapshots/\(name).png")
        try? FileManager.default.createDirectory(
            at: saved.deletingLastPathComponent(), withIntermediateDirectories: true)
        return write(image, to: saved)
            ? "This run's image is at \(saved.path)."
            : "Couldn't save this run's image to \(saved.path)."
    }

    /// The image's pixels as RGBA8, premultiplied, in sRGB.
    static func pixels(of image: CGImage) -> [UInt8]? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drew = data.withUnsafeMutableBytes { bytes -> Bool in
            guard
                let context = CGContext(
                    data: bytes.baseAddress, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return drew ? data : nil
    }

    private static func write(_ image: CGImage, to url: URL) -> Bool {
        guard
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }
}
