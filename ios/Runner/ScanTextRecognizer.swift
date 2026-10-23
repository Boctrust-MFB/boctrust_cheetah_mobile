import CoreVideo
import Flutter
import ImageIO
import Vision

/// Reads the lines of text on a photo or camera frame with Vision for Scan to Pay, over the
/// `boctrust/scan_text` channel. Boxes are returned top-left, normalized to
/// the upright image.
enum ScanTextRecognizer {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "boctrust/scan_text", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any]
      switch call.method {
      case "recognizeImage":
        guard let path = args?["path"] as? String else {
          result(FlutterError(code: "invalid_argument", message: "A path is required.", details: nil))
          return
        }
        run(on: .global(qos: .userInitiated), result) {
          try recognizeLines(at: URL(fileURLWithPath: path))
        }
      case "recognizeFrame":
        guard
          let bytes = (args?["bytes"] as? FlutterStandardTypedData)?.data,
          let width = args?["width"] as? Int,
          let height = args?["height"] as? Int,
          let bytesPerRow = args?["bytesPerRow"] as? Int,
          let rotation = args?["rotation"] as? Int,
          width > 0, height > 0, bytesPerRow >= width * 4
        else {
          result(FlutterError(code: "invalid_argument", message: "A frame is required.", details: nil))
          return
        }
        run(on: frameQueue, result) {
          try recognizeLines(
            in: bytes, width: width, height: height, bytesPerRow: bytesPerRow, rotation: rotation)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static let frameQueue = DispatchQueue(label: "boctrust.scan_text.frames", qos: .userInitiated)

  private static func run(
    on queue: DispatchQueue, _ result: @escaping FlutterResult, _ work: @escaping () throws -> [[String: Any]]
  ) {
    queue.async {
      do {
        let lines = try work()
        DispatchQueue.main.async { result(lines) }
      } catch {
        // The error may name the file; send only a fixed message.
        DispatchQueue.main.async {
          result(FlutterError(code: "recognition_failed", message: "Text recognition failed.", details: nil))
        }
      }
    }
  }

  private struct FrameError: Error {}

  private static func recognizeLines(at url: URL) throws -> [[String: Any]] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    // With the file's orientation, Vision reports boxes on the upright image.
    let handler = VNImageRequestHandler(url: url, orientation: orientation(of: url), options: [:])
    try handler.perform([request])
    return lines(from: request.results ?? [])
  }

  // A BGRA frame; `rotation` is the camera's sensor orientation, so Vision
  // reports boxes on the upright frame.
  private static func recognizeLines(
    in bytes: Data, width: Int, height: Int, bytesPerRow: Int, rotation: Int
  ) throws -> [[String: Any]] {
    var buffer: CVPixelBuffer?
    guard
      CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess,
      let buffer, bytes.count >= bytesPerRow * (height - 1) + width * 4
    else { throw FrameError() }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let target = CVPixelBufferGetBaseAddress(buffer) else { throw FrameError() }
    let targetStride = CVPixelBufferGetBytesPerRow(buffer)
    bytes.withUnsafeBytes { source in
      for row in 0..<height {
        memcpy(target + row * targetStride, source.baseAddress! + row * bytesPerRow, width * 4)
      }
    }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    let orientation: CGImagePropertyOrientation
    switch rotation {
    case 90: orientation = .right
    case 180: orientation = .down
    case 270: orientation = .left
    default: orientation = .up
    }
    try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation, options: [:]).perform([request])
    return lines(from: request.results ?? [])
  }

  private static func lines(from observations: [VNRecognizedTextObservation]) -> [[String: Any]] {
    observations.compactMap { observation in
      guard let candidate = observation.topCandidates(1).first else { return nil }
      // Vision's origin is bottom-left; the shared contract is top-left.
      let box = observation.boundingBox
      // Boxes can overhang the image a little; keep the visible part, as Android does.
      let left = min(max(Double(box.origin.x), 0), 1)
      let top = min(max(Double(1 - (box.origin.y + box.height)), 0), 1)
      let right = min(max(Double(box.origin.x + box.width), left), 1)
      let bottom = min(max(Double(1 - box.origin.y), top), 1)
      return [
        "text": candidate.string,
        "left": left,
        "top": top,
        "width": right - left,
        "height": bottom - top,
      ]
    }
  }

  private static func orientation(of url: URL) -> CGImagePropertyOrientation {
    guard
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let raw = properties[kCGImagePropertyOrientation] as? UInt32,
      let orientation = CGImagePropertyOrientation(rawValue: raw)
    else { return .up }
    return orientation
  }
}
