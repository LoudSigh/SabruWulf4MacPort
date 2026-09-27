import Foundation

private enum TapeError: Error, CustomStringConvertible {
    case invalidHeader
    case truncated(offset: Int, needed: Int)
    case unsupportedBlock(id: UInt8, offset: Int)
    case invalidLength(offset: Int, value: UInt32)
    case invalidChecksum(offset: Int)
    case invalidBasicProgram(offset: Int, line: Int, length: Int)

    var description: String {
        switch self {
        case .invalidHeader:
            return "Invalid TZX signature or missing version"
        case let .truncated(offset, needed):
            return "Truncated TZX at offset \(offset); need \(needed) more byte(s)"
        case let .unsupportedBlock(id, offset):
            return String(format: "Unsupported TZX block 0x%02X at offset %d", id, offset)
        case let .invalidLength(offset, value):
            return "Invalid length \(value) at offset \(offset)"
        case let .invalidChecksum(offset):
            return "Invalid standard data block checksum at offset \(offset)"
        case let .invalidBasicProgram(offset, line, length):
            return "Invalid BASIC line structure at offset \(offset), line \(line), length \(length)"
        }
    }
}

private struct Reader {
    let bytes: [UInt8]
    private(set) var position = 0

    mutating func byte() throws -> UInt8 {
        guard position < bytes.count else {
            throw TapeError.truncated(offset: position, needed: 1)
        }
        defer { position += 1 }
        return bytes[position]
    }

    mutating func word() throws -> Int {
        let low = try Int(byte())
        let high = try Int(byte())
        return low | (high << 8)
    }

    mutating func threeBytes() throws -> Int {
        let low = try word()
        return low | (try Int(byte()) << 16)
    }

    mutating func dword() throws -> UInt32 {
        let low = try UInt32(word())
        let high = try UInt32(word())
        return low | (high << 16)
    }

    mutating func slice(_ count: Int) throws -> ArraySlice<UInt8> {
        guard count >= 0, count <= bytes.count - position else {
            throw TapeError.truncated(offset: position, needed: max(count, 0))
        }
        defer { position += count }
        return bytes[position..<(position + count)]
    }

    mutating func sizedDword() throws {
        let offset = position
        let length = try dword()
        guard let count = Int(exactly: length) else {
            throw TapeError.invalidLength(offset: offset, value: length)
        }
        _ = try slice(count)
    }
}

private struct BlockReport: Encodable {
    let index: Int
    let offset: Int
    let id: String
    let length: Int
    let dataLength: Int?
    let xorZero: Bool?
    let checksumValid: Bool?
    let headerType: String?
    let headerName: String?
    let declaredLoadAddress: Int?
    let declaredDataLength: Int?
    let autostartLine: Int?
    let variableAreaOffset: Int?
    let changesPlaybackOrder: Bool
}

private struct TapeReport: Encodable {
    let version: String
    let byteLength: Int
    let blocks: [BlockReport]
    let playbackOrderRequiresInterpretation: Bool
    let requiresPulseTiming: Bool
    let basicProgram: BasicProgramReport?
    let basicProgramParseError: String?
}

private struct BasicProgramReport: Encodable {
    let lineNumbers: [Int]
    let lineCount: Int
    let programBytes: Int
    let variableAreaOffset: Int
}

private func basicLines(_ data: ArraySlice<UInt8>, offset: Int) throws -> [Int] {
    let bytes = Array(data)
    var cursor = 0
    var numbers: [Int] = []
    while cursor < bytes.count {
        guard bytes.count - cursor >= 4 else {
            throw TapeError.invalidBasicProgram(offset: offset + cursor, line: -1, length: -1)
        }
        let number = Int(bytes[cursor]) << 8 | Int(bytes[cursor + 1])
        let length = Int(bytes[cursor + 2]) | Int(bytes[cursor + 3]) << 8
        cursor += 4
        guard length > 0, length <= bytes.count - cursor,
              bytes[cursor + length - 1] == 0x0D
        else {
            throw TapeError.invalidBasicProgram(
                offset: offset + cursor, line: number, length: length
            )
        }
        numbers.append(number)
        cursor += length
    }
    return numbers
}

private func inspect(_ bytes: [UInt8]) throws -> TapeReport {
    guard bytes.count >= 10,
          Array(bytes[0..<8]) == [0x5A, 0x58, 0x54, 0x61, 0x70, 0x65, 0x21, 0x1A]
    else {
        throw TapeError.invalidHeader
    }
    var reader = Reader(bytes: bytes)
    _ = try reader.slice(8)
    let major = try reader.byte()
    let minor = try reader.byte()
    var blocks: [BlockReport] = []
    var pendingProgram: (length: Int, variableOffset: Int)?
    var basicProgram: BasicProgramReport?
    var basicProgramParseError: String?

    while reader.position < bytes.count {
        let start = reader.position
        let id = try reader.byte()
        var payload: ArraySlice<UInt8>?
        var isControl = false

        switch id {
        case 0x10:
            _ = try reader.word()
            payload = try reader.slice(reader.word())
        case 0x11:
            _ = try reader.slice(15)
            payload = try reader.slice(reader.threeBytes())
        case 0x12:
            _ = try reader.slice(4)
        case 0x13:
            _ = try reader.slice(Int(reader.byte()) * 2)
        case 0x14:
            _ = try reader.slice(7)
            payload = try reader.slice(reader.threeBytes())
        case 0x15:
            _ = try reader.slice(5)
            payload = try reader.slice(reader.threeBytes())
        case 0x18, 0x19:
            try reader.sizedDword()
        case 0x20:
            _ = try reader.word()
        case 0x21, 0x30:
            _ = try reader.slice(Int(reader.byte()))
        case 0x22, 0x25, 0x27:
            isControl = id == 0x25 || id == 0x27
        case 0x23, 0x24:
            _ = try reader.slice(2)
            isControl = true
        case 0x26:
            _ = try reader.slice(try reader.word() * 2)
            isControl = true
        case 0x28:
            _ = try reader.slice(try reader.word())
            isControl = true
        case 0x2A, 0x2B:
            try reader.sizedDword()
            isControl = true
        case 0x31:
            _ = try reader.byte()
            _ = try reader.slice(Int(reader.byte()))
        case 0x32:
            _ = try reader.slice(try reader.word())
        case 0x33:
            _ = try reader.slice(Int(reader.byte()) * 3)
        case 0x35:
            _ = try reader.slice(16)
            try reader.sizedDword()
        default:
            throw TapeError.unsupportedBlock(id: id, offset: start)
        }

        var name: String?
        var headerType: String?
        var address: Int?
        var declaredLength: Int?
        var autostartLine: Int?
        var variableAreaOffset: Int?
        var xorZero: Bool?
        var checksum: Bool?
        if let payload, id == 0x10 || id == 0x11 || id == 0x14 {
            xorZero = payload.reduce(UInt8(0), ^) == 0
            if id == 0x10 {
                checksum = xorZero
            }
            if id == 0x10, checksum == false {
                throw TapeError.invalidChecksum(offset: start)
            }
            if payload.count == 19, payload.first == 0 {
                let startIndex = payload.startIndex
                let type = payload[startIndex + 1]
                headerType = switch type {
                case 0: "program"
                case 1: "numberArray"
                case 2: "characterArray"
                case 3: "code"
                default: "unknown(\(type))"
                }
                name = String(
                    decoding: payload[(startIndex + 2)..<(startIndex + 12)],
                    as: UTF8.self
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                declaredLength = Int(payload[startIndex + 12])
                    | (Int(payload[startIndex + 13]) << 8)
                let parameter1 = Int(payload[startIndex + 14])
                    | (Int(payload[startIndex + 15]) << 8)
                let parameter2 = Int(payload[startIndex + 16])
                    | (Int(payload[startIndex + 17]) << 8)
                if type == 3 {
                    address = parameter1
                } else if type == 0 {
                    autostartLine = parameter1
                    variableAreaOffset = parameter2
                }
            }
        }
        if id == 0x10, headerType == "program",
           let declaredLength, let variableAreaOffset
        {
            pendingProgram = (declaredLength, variableAreaOffset)
        } else if id == 0x10, let pending = pendingProgram, let payload,
                  payload.first == 0xFF
        {
            guard payload.count == pending.length + 2,
                  pending.variableOffset <= pending.length
            else {
                throw TapeError.invalidBasicProgram(
                    offset: start, line: -1, length: pending.length
                )
            }
            let programStart = payload.startIndex + 1
            do {
                let lines = try basicLines(
                    payload[programStart..<(programStart + pending.variableOffset)],
                    offset: start
                )
                basicProgram = BasicProgramReport(
                    lineNumbers: lines,
                    lineCount: lines.count,
                    programBytes: pending.length,
                    variableAreaOffset: pending.variableOffset
                )
            } catch let error as TapeError {
                basicProgramParseError = error.description
            }
            pendingProgram = nil
        }

        blocks.append(
            BlockReport(
                index: blocks.count,
                offset: start,
                id: String(format: "0x%02X", id),
                length: reader.position - start,
                dataLength: payload?.count,
                xorZero: xorZero,
                checksumValid: checksum,
                headerType: headerType,
                headerName: name,
                declaredLoadAddress: address,
                declaredDataLength: declaredLength,
                autostartLine: autostartLine,
                variableAreaOffset: variableAreaOffset,
                changesPlaybackOrder: isControl
            )
        )
    }

    return TapeReport(
        version: "\(major).\(minor)",
        byteLength: bytes.count,
        blocks: blocks,
        playbackOrderRequiresInterpretation: blocks.contains { $0.changesPlaybackOrder },
        requiresPulseTiming: blocks.contains {
            ["0x12", "0x13", "0x14", "0x15", "0x18", "0x19"].contains($0.id)
        },
        basicProgram: basicProgram,
        basicProgramParseError: basicProgramParseError
    )
}

private func selfTest() throws {
    let signature: [UInt8] = [0x5A, 0x58, 0x54, 0x61, 0x70, 0x65, 0x21, 0x1A, 1, 10]
    let archive: [UInt8] = [0x30, 1, 0x41]
    let standard: [UInt8] = [0x10, 0, 0, 3, 0, 0xFF, 1, 0xFE]
    let result = try inspect(signature + archive + standard)
    precondition(result.blocks.count == 2)
    precondition(result.blocks[1].checksumValid == true)
    precondition(result.blocks[1].offset == 13)
    let programHeader: [UInt8] = [
        0, 0, 83, 65, 66, 82, 69, 32, 32, 32, 32, 32,
        0x1A, 0x06, 0, 0, 0x9E, 0
    ]
    let headerChecksum = programHeader.reduce(UInt8(0), ^)
    let header = [UInt8(0x10), 0, 0, 19, 0] + programHeader + [headerChecksum]
    let metadata = try inspect(signature + header).blocks[0]
    precondition(metadata.headerType == "program")
    precondition(metadata.headerName == "SABRE")
    precondition(metadata.declaredDataLength == 1562)
    precondition(metadata.variableAreaOffset == 158)
    let syntheticLines = try basicLines([0, 10, 2, 0, 0xEA, 0x0D][...], offset: 0)
    precondition(syntheticLines == [10])
    do {
        _ = try inspect(signature + [0x10, 0, 0, 4, 0, 0xFF])
        preconditionFailure("Truncated data should fail")
    } catch TapeError.truncated {
        // Expected: a length field may never read beyond the tape.
    }
    do {
        _ = try inspect(signature + [0x77])
        preconditionFailure("Unknown block should fail")
    } catch TapeError.unsupportedBlock {
        // Expected: do not guess the size of an unknown block.
    }
    do {
        _ = try inspect(signature + [0x10, 0, 0, 3, 0, 0xFF, 1, 0])
        preconditionFailure("Corrupt standard data should fail")
    } catch TapeError.invalidChecksum {
        // Expected: standard block XOR over flag, payload and check byte must be zero.
    }
    print("TapeInventory self-test passed")
}

@main
private struct TapeInventory {
    static func main() {
        do {
            guard CommandLine.arguments.count == 2 else {
                fputs("Usage: TapeInventory <file.tzx> | --self-test\n", stderr)
                exit(2)
            }
            if CommandLine.arguments[1] == "--self-test" {
                try selfTest()
                return
            }
            let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            let report = try inspect(Array(data))
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let output = try encoder.encode(report)
            FileHandle.standardOutput.write(output)
            FileHandle.standardOutput.write(Data([0x0A]))
        } catch {
            fputs("TapeInventory: \(error)\n", stderr)
            exit(1)
        }
    }
}
