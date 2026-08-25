import CryptoKit
import Darwin
import Foundation

private enum VerificationFailure: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case let .message(value):
            return value
        }
    }
}

private struct Arguments {
    let publicKey: String
    let appcastURL: URL
    let archiveURL: URL
    let archiveSignature: String

    init(commandLine: [String]) throws {
        let supported = Set([
            "--public-key",
            "--appcast",
            "--archive",
            "--archive-signature",
        ])
        var values: [String: String] = [:]
        var index = 1
        while index < commandLine.count {
            let option = commandLine[index]
            guard supported.contains(option), index + 1 < commandLine.count else {
                throw VerificationFailure.message("invalid argument: \(option)")
            }
            guard values[option] == nil else {
                throw VerificationFailure.message("duplicate argument: \(option)")
            }
            values[option] = commandLine[index + 1]
            index += 2
        }
        guard values.count == supported.count,
              let publicKey = values["--public-key"],
              let appcastPath = values["--appcast"],
              let archivePath = values["--archive"],
              let archiveSignature = values["--archive-signature"]
        else {
            throw VerificationFailure.message(
                "required arguments: --public-key --appcast --archive --archive-signature"
            )
        }
        self.publicKey = publicKey
        appcastURL = URL(fileURLWithPath: appcastPath).standardizedFileURL
        archiveURL = URL(fileURLWithPath: archivePath).standardizedFileURL
        self.archiveSignature = archiveSignature
    }
}

private struct SignedAppcastContent {
    let content: Data
    let signature: Data
}

private func decodedBase64(
    _ value: String,
    expectedLength: Int,
    label: String
) throws -> Data {
    guard let data = Data(base64Encoded: value), data.count == expectedLength else {
        throw VerificationFailure.message("invalid \(label)")
    }
    return data
}

private func signedAppcastContent(from data: Data) throws -> SignedAppcastContent {
    let marker = Data("<!-- sparkle-signatures:\n".utf8)
    guard let markerRange = data.range(of: marker, options: .backwards) else {
        throw VerificationFailure.message("appcast signature block is missing")
    }
    let content = Data(data[..<markerRange.lowerBound])
    guard var lines = String(
        data: data[markerRange.lowerBound...],
        encoding: .utf8
    )?.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) else {
        throw VerificationFailure.message("appcast signature block is not UTF-8")
    }
    if lines.last == "" {
        lines.removeLast()
    }
    guard lines.count == 4,
          lines[0] == "<!-- sparkle-signatures:",
          lines[1].hasPrefix("edSignature: "),
          lines[2].hasPrefix("length: "),
          lines[3] == "-->",
          let expectedLength = Int(lines[2].dropFirst("length: ".count)),
          expectedLength == content.count
    else {
        throw VerificationFailure.message("appcast signature block is invalid")
    }
    let signature = try decodedBase64(
        String(lines[1].dropFirst("edSignature: ".count)),
        expectedLength: 64,
        label: "appcast signature"
    )
    return SignedAppcastContent(content: content, signature: signature)
}

@main
private struct SparkleSignatureVerifier {
    static func main() {
        do {
            let arguments = try Arguments(commandLine: CommandLine.arguments)
            let publicKeyData = try decodedBase64(
                arguments.publicKey,
                expectedLength: 32,
                label: "Sparkle public key"
            )
            let publicKey = try Curve25519.Signing.PublicKey(
                rawRepresentation: publicKeyData
            )
            let appcastData = try Data(
                contentsOf: arguments.appcastURL,
                options: .mappedIfSafe
            )
            let signedAppcast = try signedAppcastContent(from: appcastData)
            guard publicKey.isValidSignature(
                signedAppcast.signature,
                for: signedAppcast.content
            ) else {
                throw VerificationFailure.message("appcast signature is invalid")
            }

            let archiveData = try Data(
                contentsOf: arguments.archiveURL,
                options: .mappedIfSafe
            )
            let archiveSignature = try decodedBase64(
                arguments.archiveSignature,
                expectedLength: 64,
                label: "archive signature"
            )
            guard publicKey.isValidSignature(archiveSignature, for: archiveData) else {
                throw VerificationFailure.message("archive signature is invalid")
            }
            print("Sparkle appcast and archive signatures are valid.")
        } catch {
            FileHandle.standardError.write(Data("ERROR: \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
}
