import Foundation
import Network

/// Configuration for an authenticated SMTP-over-TLS submission.
struct SMTPConfig {
    let host: String
    let port: UInt16
    let username: String
    let password: String
    let from: String
    let to: String
}

struct SMTPAttachment {
    let filename: String
    let mimeType: String
    let data: Data
}

struct SMTPMessage {
    let subject: String
    let body: String
    var attachment: SMTPAttachment?
}

enum SMTPError: LocalizedError {
    case connectionFailed(String)
    case unexpectedResponse(expected: Int, got: Int, message: String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let m): return "Connexion échouée : \(m)"
        case .unexpectedResponse(let e, let g, let m):
            return "Réponse SMTP inattendue (attendu \(e), reçu \(g)) : \(m)"
        case .timeout: return "Délai d'attente dépassé."
        }
    }
}

/// A minimal SMTP client speaking implicit TLS (SMTPS, typically port 465) with
/// `AUTH LOGIN`. Enough to deliver a single message with one attachment to a
/// provider such as Gmail, iCloud or Fastmail using an app-specific password.
///
/// Implicit TLS is used (rather than STARTTLS) because `NWConnection` cannot
/// upgrade a live plaintext connection to TLS mid-stream.
final class SMTPClient {

    private let config: SMTPConfig
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "com.darkweak.ensachage.smtp")
    private var buffer = ""

    private init(config: SMTPConfig) {
        self.config = config
        let params = NWParameters(tls: NWProtocolTLS.Options(), tcp: NWProtocolTCP.Options())
        self.connection = NWConnection(
            host: NWEndpoint.Host(config.host),
            port: NWEndpoint.Port(rawValue: config.port) ?? 465,
            using: params
        )
    }

    static func send(_ message: SMTPMessage, config: SMTPConfig) async throws {
        try await SMTPClient(config: config).run(message: message)
    }

    // MARK: - Conversation

    private func run(message: SMTPMessage) async throws {
        try await withTimeout(seconds: 30) {
            try await self.connect()
            defer { self.connection.cancel() }

            try await self.expect(220)
            try await self.command("EHLO Ensachage", 250)
            try await self.command("AUTH LOGIN", 334)
            try await self.command(Data(self.config.username.utf8).base64EncodedString(), 334)
            try await self.command(Data(self.config.password.utf8).base64EncodedString(), 235)
            try await self.command("MAIL FROM:<\(self.config.from)>", 250)
            try await self.command("RCPT TO:<\(self.config.to)>", 250)
            try await self.command("DATA", 354)
            try await self.sendRaw(self.buildMIME(message) + "\r\n.\r\n")
            try await self.expect(250)
            try await self.command("QUIT", 221)
        }
    }

    private func command(_ line: String, _ expected: Int) async throws {
        try await sendRaw(line + "\r\n")
        try await expect(expected)
    }

    private func expect(_ expected: Int) async throws {
        let (code, message) = try await readResponse()
        if code != expected {
            throw SMTPError.unexpectedResponse(expected: expected, got: code, message: message)
        }
    }

    // MARK: - Networking primitives

    private func connect() async throws {
        var resumed = false
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if !resumed { resumed = true; cont.resume() }
                case .failed(let error):
                    if !resumed { resumed = true; cont.resume(throwing: SMTPError.connectionFailed("\(error)")) }
                case .cancelled:
                    if !resumed { resumed = true; cont.resume(throwing: SMTPError.connectionFailed("annulé")) }
                default:
                    break // .waiting is transient — rely on the overall timeout
                }
            }
            connection.start(queue: queue)
        }
    }

    private func sendRaw(_ string: String) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: Data(string.utf8), completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }

    private func receive() async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                if let error { cont.resume(throwing: error) } else { cont.resume(returning: data ?? Data()) }
            }
        }
    }

    /// Reads until a complete SMTP reply is buffered, returning (code, message).
    private func readResponse() async throws -> (Int, String) {
        while true {
            if let parsed = Self.parseComplete(buffer) {
                buffer = ""
                return parsed
            }
            let chunk = try await receive()
            guard !chunk.isEmpty else {
                throw SMTPError.connectionFailed("Connexion fermée par le serveur")
            }
            buffer += String(decoding: chunk, as: UTF8.self)
        }
    }

    /// A reply is complete when its last line is `NNN ` (digits + space, not `-`).
    private static func parseComplete(_ s: String) -> (Int, String)? {
        let lines = s.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        guard let last = lines.last, last.count >= 4 else { return nil }
        let sep = last.index(last.startIndex, offsetBy: 3)
        guard last[sep] == " ", let code = Int(last.prefix(3)) else { return nil }
        let message = lines.map { $0.count > 4 ? String($0.dropFirst(4)) : "" }.joined(separator: " ")
        return (code, message)
    }

    // MARK: - MIME

    private func buildMIME(_ message: SMTPMessage) -> String {
        var out = ""
        out += "From: \(config.from)\r\n"
        out += "To: \(config.to)\r\n"
        out += "Subject: \(Self.encodeHeader(message.subject))\r\n"
        out += "Date: \(Self.rfc822Date())\r\n"
        out += "MIME-Version: 1.0\r\n"

        guard let attachment = message.attachment else {
            out += "Content-Type: text/plain; charset=utf-8\r\n\r\n"
            out += Self.dotStuff(message.body)
            return out
        }

        let boundary = "ensachage-\(UInt64(Date().timeIntervalSince1970))-boundary"
        out += "Content-Type: multipart/mixed; boundary=\"\(boundary)\"\r\n\r\n"
        out += "--\(boundary)\r\n"
        out += "Content-Type: text/plain; charset=utf-8\r\n\r\n"
        out += Self.dotStuff(message.body) + "\r\n"
        out += "--\(boundary)\r\n"
        out += "Content-Type: \(attachment.mimeType); name=\"\(attachment.filename)\"\r\n"
        out += "Content-Transfer-Encoding: base64\r\n"
        out += "Content-Disposition: attachment; filename=\"\(attachment.filename)\"\r\n\r\n"
        out += attachment.data.base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn])
        out += "\r\n--\(boundary)--\r\n"
        return out
    }

    /// RFC 2047 encoded-word for non-ASCII headers (e.g. the 🍏 in the subject).
    private static func encodeHeader(_ s: String) -> String {
        guard !s.allSatisfy(\.isASCII) else { return s }
        return "=?UTF-8?B?\(Data(s.utf8).base64EncodedString())?="
    }

    /// CRLF-normalize and dot-stuff the body (RFC 5321 §4.5.2).
    private static func dotStuff(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.hasPrefix(".") ? "." + $0 : $0 }
            .joined(separator: "\r\n")
    }

    private static func rfc822Date() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f.string(from: Date())
    }

    // MARK: - Timeout

    private func withTimeout(seconds: Double, _ operation: @escaping () async throws -> Void) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw SMTPError.timeout
            }
            try await group.next()
            group.cancelAll()
        }
    }
}
