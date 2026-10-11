import CLiveSplitCore
import CoreGraphics
import Foundation

/// One frame from `LayoutRenderer`.
public struct RenderedFrame: Sendable {
    /// The new image, or `nil` when nothing changed since the last frame.
    public let image: CGImage?
    /// The layout's natural size in pixels, after its height changed (spec §5.2).
    public let sizeHint: CGSize?

    /// No new image and no hint.
    public static let nothing = RenderedFrame(image: nil, sizeHint: nil)
}

/// Draws a layout state with livesplit-core's software renderer, through core/'s renderer, which
/// skips frames when nothing changed (spec §5.2, §5.3). Not thread-safe: use one thread.
public final class LayoutRenderer {
    /// The largest width or height drawn, in pixels. Anything larger draws nothing, so a
    /// hand-edited window frame can't ask for gigabytes.
    public static let maximumSide = 16_384

    private let ptr: UnsafeMutableRawPointer
    /// The pixels livesplit-core draws into. The same buffer every frame, since it only redraws
    /// what changed; replaced, and drawn whole, when the size changes.
    private var buffer: [UInt8] = []
    private var width = 0
    private var height = 0

    public init() {
        ptr = LsoRenderer_new()
    }

    deinit {
        LsoRenderer_drop(ptr)
    }

    /// Renders `state` at `width` × `height` pixels, if it or the size changed since the last
    /// frame.
    public func render(
        _ state: LayoutStateRef, _ imageCache: ImageCacheRef, width: Int, height: Int
    )
        -> RenderedFrame
    {
        precondition(state.ptr != nil && imageCache.ptr != nil)
        guard (1...Self.maximumSide).contains(width), (1...Self.maximumSide).contains(height)
        else { return .nothing }
        if width != self.width || height != self.height {
            buffer = [UInt8](repeating: 0, count: width * height * 4)
            self.width = width
            self.height = height
        }
        let result = buffer.withUnsafeMutableBufferPointer { pixels in
            LsoRenderer_render(
                ptr, state.ptr, imageCache.ptr, pixels.baseAddress, UInt32(width), UInt32(height),
                UInt32(width))
        }
        let sizeHint =
            result.has_size_hint
            ? CGSize(
                width: CGFloat(result.size_hint_width), height: CGFloat(result.size_hint_height))
            : nil
        return RenderedFrame(image: result.drew ? makeImage() : nil, sizeHint: sizeHint)
    }

    /// A copy of the buffer as an image. A copy, because the next frame draws into the buffer
    /// while this image may still be on screen.
    private func makeImage() -> CGImage? {
        guard let provider = CGDataProvider(data: Data(buffer) as CFData),
            let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
