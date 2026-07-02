import AVFoundation

/// Captures a single still frame from the default video device using AVFoundation.
///
/// The capture session is configured lazily and runs on a dedicated serial queue.
/// A short warm-up delay lets exposure/white-balance settle before the frame is
/// grabbed, then the session is stopped to release the camera (and turn off the
/// indicator light) until the next failed login.
final class CameraCapture: NSObject {

    static let shared = CameraCapture()

    enum Authorization {
        case authorized, denied, notDetermined
    }

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "com.darkweak.ensachage.camera")
    private var isConfigured = false
    private var continuation: CheckedContinuation<Data?, Never>?

    var authorizationStatus: Authorization {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    /// Triggers the system permission prompt (first launch) and returns the result.
    func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    /// Captures one JPEG frame, or `nil` if the camera is unavailable / unauthorized.
    func captureSnapshot() async -> Data? {
        guard authorizationStatus == .authorized else { return nil }
        return await withCheckedContinuation { continuation in
            queue.async {
                guard self.configureIfNeeded() else {
                    continuation.resume(returning: nil)
                    return
                }
                self.continuation = continuation
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                // Allow the sensor to warm up before grabbing the frame.
                self.queue.asyncAfter(deadline: .now() + 0.7) {
                    guard self.session.isRunning else {
                        self.finish(with: nil)
                        return
                    }
                    let settings: AVCapturePhotoSettings
                    if self.photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                        settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                    } else {
                        settings = AVCapturePhotoSettings()
                    }
                    self.photoOutput.capturePhoto(with: settings, delegate: self)
                }
            }
        }
    }

    // MARK: - Private

    private func configureIfNeeded() -> Bool {
        if isConfigured { return true }
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            return false
        }
        session.addInput(input)
        session.addOutput(photoOutput)
        session.commitConfiguration()
        isConfigured = true
        return true
    }

    private func finish(with data: Data?) {
        let pending = continuation
        continuation = nil
        if session.isRunning {
            session.stopRunning()
        }
        pending?.resume(returning: data)
    }
}

extension CameraCapture: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        queue.async {
            self.finish(with: error == nil ? photo.fileDataRepresentation() : nil)
        }
    }
}
