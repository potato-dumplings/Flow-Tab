import Foundation

struct RuntimeLogPrivacyCodec {
    private static let recordPrefix = "privacy=v2"
    private static let fingerprintByteCount = 12
    private let lineHeaderCodec = RuntimeLogPrivacyLineHeaderCodec()

    func encode(_ envelope: RuntimeLogPrivacyEnvelope) -> String {
        let message = encodeMetadata(envelope.message)
        let event = envelope.event.map(encodeMetadata) ?? "-"
        let fields = envelope.fields.isEmpty
            ? "-"
            : envelope.fields.map(encodeField).joined(separator: ";")
        return "\(Self.recordPrefix) m=\(message) e=\(event) f=\(fields)"
    }

    func encodeLine(
        timestamp: String,
        level: RuntimeLogLevel,
        category: String,
        envelope: RuntimeLogPrivacyEnvelope
    ) -> String {
        lineHeaderCodec.compactHeader(
            timestamp: timestamp,
            level: level,
            category: category
        ) + encode(envelope)
    }

    func decode(_ record: String) -> RuntimeLogPrivacyEnvelope? {
        let components = record.split(
            separator: " ",
            omittingEmptySubsequences: false
        )
        guard components.count == 4,
              components[0] == Self.recordPrefix,
              components[1].hasPrefix("m="),
              components[2].hasPrefix("e="),
              components[3].hasPrefix("f=")
        else {
            return nil
        }

        guard let message = decodeMetadata(components[1].dropFirst(2)) else {
            return nil
        }

        let eventPayload = components[2].dropFirst(2)
        let event: RuntimeLogPrivacyEnvelope.ValueMetadata?
        if eventPayload == "-" {
            event = nil
        } else {
            guard let decodedEvent = decodeMetadata(eventPayload) else {
                return nil
            }
            event = decodedEvent
        }

        let fieldsPayload = components[3].dropFirst(2)
        let fields: [RuntimeLogPrivacyEnvelope.Field]
        if fieldsPayload == "-" {
            fields = []
        } else {
            let fieldComponents = fieldsPayload.split(
                separator: ";",
                omittingEmptySubsequences: false
            )
            var decodedFields: [RuntimeLogPrivacyEnvelope.Field] = []
            decodedFields.reserveCapacity(fieldComponents.count)
            for fieldComponent in fieldComponents {
                guard let field = decodeField(fieldComponent) else {
                    return nil
                }
                decodedFields.append(field)
            }
            fields = decodedFields
        }

        guard message.count == fields.count else { return nil }
        return RuntimeLogPrivacyEnvelope(
            message: message,
            event: event,
            fields: fields
        )
    }

    func expandedMessage(for envelope: RuntimeLogPrivacyEnvelope) -> String {
        var tokens = [
            "message.type=structured",
            "message.length=\(envelope.message.length)",
            "message.fieldCount=\(envelope.fields.count)",
            "message.fingerprint=\(hexFingerprint(envelope.message.fingerprint))"
        ]
        if let event = envelope.event {
            tokens.append(contentsOf: metadataTokens(
                prefix: "event",
                type: "event",
                metadata: event
            ))
        }
        for (index, field) in envelope.fields.enumerated() {
            tokens.append(contentsOf: metadataTokens(
                prefix: "field\(index).name",
                type: "field-name",
                metadata: field.name
            ))
            tokens.append(contentsOf: metadataTokens(
                prefix: "field\(index).value",
                type: field.valueType.rawValue,
                metadata: field.value
            ))
        }
        return tokens.joined(separator: " ")
    }

    func expandLineForDisplay(_ line: String) -> String {
        let payloadPrefix = Self.recordPrefix + " m="
        guard let payloadRange = line.range(of: payloadPrefix) else {
            return line
        }
        let header = line[..<payloadRange.lowerBound]
        let record = String(line[payloadRange.lowerBound...])
        guard let envelope = decode(record) else { return line }
        if header.isEmpty {
            return expandedMessage(for: envelope)
        }
        if let expandedHeader = lineHeaderCodec.expand(header) {
            return expandedHeader + expandedMessage(for: envelope)
        }
        guard header.hasSuffix("] ") else { return line }
        return String(header) + expandedMessage(for: envelope)
    }

    private func encodeMetadata(
        _ metadata: RuntimeLogPrivacyEnvelope.ValueMetadata
    ) -> String {
        "\(metadata.length),\(metadata.count),\(base64URLFingerprint(metadata.fingerprint))"
    }

    private func encodeField(_ field: RuntimeLogPrivacyEnvelope.Field) -> String {
        [
            String(field.name.length),
            base64URLFingerprint(field.name.fingerprint),
            String(field.valueType.code),
            String(field.value.length),
            String(field.value.count),
            base64URLFingerprint(field.value.fingerprint)
        ].joined(separator: ",")
    }

    private func decodeMetadata(
        _ payload: Substring
    ) -> RuntimeLogPrivacyEnvelope.ValueMetadata? {
        let components = payload.split(
            separator: ",",
            omittingEmptySubsequences: false
        )
        guard components.count == 3,
              let length = nonnegativeInteger(components[0]),
              let count = nonnegativeInteger(components[1]),
              let fingerprint = decodeBase64URLFingerprint(components[2])
        else {
            return nil
        }
        return RuntimeLogPrivacyEnvelope.ValueMetadata(
            length: length,
            count: count,
            fingerprint: fingerprint
        )
    }

    private func decodeField(
        _ payload: Substring
    ) -> RuntimeLogPrivacyEnvelope.Field? {
        let components = payload.split(
            separator: ",",
            omittingEmptySubsequences: false
        )
        guard components.count == 6,
              let nameLength = nonnegativeInteger(components[0]),
              let nameFingerprint = decodeBase64URLFingerprint(components[1]),
              let valueType = RuntimeLogPrivacyEnvelope.ValueType(
                  code: components[2]
              ),
              let valueLength = nonnegativeInteger(components[3]),
              let valueCount = nonnegativeInteger(components[4]),
              let valueFingerprint = decodeBase64URLFingerprint(components[5])
        else {
            return nil
        }
        return RuntimeLogPrivacyEnvelope.Field(
            name: RuntimeLogPrivacyEnvelope.ValueMetadata(
                length: nameLength,
                count: 1,
                fingerprint: nameFingerprint
            ),
            valueType: valueType,
            value: RuntimeLogPrivacyEnvelope.ValueMetadata(
                length: valueLength,
                count: valueCount,
                fingerprint: valueFingerprint
            )
        )
    }

    private func nonnegativeInteger(_ value: Substring) -> Int? {
        guard !value.isEmpty,
              value.allSatisfy({ $0.isASCII && $0.isNumber }),
              let number = Int(value),
              number >= 0
        else {
            return nil
        }
        return number
    }

    private func base64URLFingerprint(_ fingerprint: Data) -> String {
        precondition(fingerprint.count == Self.fingerprintByteCount)
        return fingerprint.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func decodeBase64URLFingerprint(_ value: Substring) -> Data? {
        guard value.count == 16,
              value.allSatisfy({ character in
                  character.isASCII
                      && (character.isLetter
                          || character.isNumber
                          || character == "-"
                          || character == "_")
              })
        else {
            return nil
        }
        let base64 = String(value)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: base64),
              data.count == Self.fingerprintByteCount
        else {
            return nil
        }
        return data
    }

    private func hexFingerprint(_ fingerprint: Data) -> String {
        precondition(fingerprint.count == Self.fingerprintByteCount)
        let digits = Array("0123456789abcdef".utf8)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(Self.fingerprintByteCount * 2)
        for byte in fingerprint {
            bytes.append(digits[Int(byte >> 4)])
            bytes.append(digits[Int(byte & 0x0F)])
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func metadataTokens(
        prefix: String,
        type: String,
        metadata: RuntimeLogPrivacyEnvelope.ValueMetadata
    ) -> [String] {
        [
            "\(prefix).type=\(type)",
            "\(prefix).length=\(metadata.length)",
            "\(prefix).count=\(metadata.count)",
            "\(prefix).fingerprint=\(hexFingerprint(metadata.fingerprint))"
        ]
    }
}
