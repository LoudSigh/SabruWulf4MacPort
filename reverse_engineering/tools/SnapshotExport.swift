import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

private enum ExportError: Error, CustomStringConvertible {
    case usage
    case unsupportedSnapshot
    case unsafeDirectory
    case existingOutputMismatch
    case invalidROM
    case renderFailed

    var description: String {
        switch self {
        case .usage:
            return "Usage: SnapshotExport <snapshot.z80> [--screen <48k.rom>] (run from repository root)"
        case .unsupportedSnapshot:
            return "Only flat ZX Spectrum 48K snapshots with 49152 RAM bytes are supported"
        case .unsafeDirectory:
            return "Run from the repository root with an ignored, non-symlink private directory"
        case .existingOutputMismatch:
            return "An existing RAM export has the same filename but different contents"
        case .invalidROM:
            return "Screen export requires a 16384-byte 48K reference ROM"
        case .renderFailed:
            return "Unable to encode the 256x192 snapshot display as PNG"
        }
    }
}

private func sha256(_ bytes: [UInt8]) -> String {
    SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
}

private func writePrivate(_ bytes: Data, to output: URL) throws {
    if FileManager.default.fileExists(atPath: output.path) {
        let previous = try Data(contentsOf: output)
        guard previous == bytes else { throw ExportError.existingOutputMismatch }
    } else {
        try bytes.write(to: output, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: output.path
        )
    }
}

private func screenPNG(snapshot: Z80Snapshot, rom: [UInt8]) throws -> Data {
    guard rom.count == 0x4000 else { throw ExportError.invalidROM }
    let emulator = Speccy48Emulator(rom: rom)
    emulator.apply(snapshot: snapshot)
    let pixels = ULA.render(mem: emulator.mem, flashOn: false)
    let provider = CGDataProvider(data: Data(pixels) as CFData)
    let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
        CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)
    )
    guard let provider,
          let image = CGImage(
            width: 256, height: 192, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 1024, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo, provider: provider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent
          ),
          let output = CFDataCreateMutable(nil, 0),
          let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
          )
    else {
        throw ExportError.renderFailed
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw ExportError.renderFailed }
    return output as Data
}

@main
private struct SnapshotExport {
    static func main() {
        do {
            guard CommandLine.arguments.count == 2
                  || (CommandLine.arguments.count == 4 && CommandLine.arguments[2] == "--screen")
            else {
                throw ExportError.usage
            }
            let url = URL(fileURLWithPath: CommandLine.arguments[1])
            let input = try [UInt8](Data(contentsOf: url))
            let snapshot = try Z80Snapshot.load(from: Data(input))
            guard snapshot.ram128Banks == nil, snapshot.ram48.count == 0xC000 else {
                throw ExportError.unsupportedSnapshot
            }

            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let ignoreFile = root.appendingPathComponent(".gitignore")
            guard FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "reverse_engineering/tools/SnapshotExport.swift"
                ).path
            ),
                let ignoreRules = try? String(contentsOf: ignoreFile, encoding: .utf8),
                ignoreRules.components(separatedBy: .newlines).contains("reverse_engineering/private/")
            else {
                throw ExportError.unsafeDirectory
            }
            let privateDirectory = root
                .appendingPathComponent("reverse_engineering/private", isDirectory: true)
            if FileManager.default.fileExists(atPath: privateDirectory.path) {
                let values = try privateDirectory.resourceValues(forKeys: [.isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { throw ExportError.unsafeDirectory }
            }
            try FileManager.default.createDirectory(
                at: privateDirectory, withIntermediateDirectories: true
            )
            let name = "snapshot-\(sha256(input).prefix(12))-48k.bin"
            let output = privateDirectory.appendingPathComponent(name)
            let bytes = Data(snapshot.ram48)
            try writePrivate(bytes, to: output)
            print(
                "snapshot_sha256=\(sha256(input)) ram_sha256=\(sha256(snapshot.ram48)) "
                    + "ram_bytes=\(snapshot.ram48.count) private_output=\(output.path)"
            )
            if CommandLine.arguments.count == 4 {
                let rom = try [UInt8](
                    Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
                )
                let png = try screenPNG(snapshot: snapshot, rom: rom)
                let imageURL = privateDirectory.appendingPathComponent(
                    "snapshot-\(sha256(input).prefix(12))-screen.png"
                )
                try writePrivate(png, to: imageURL)
                print("private_screen_png=\(imageURL.path)")
            }
        } catch {
            fputs("SnapshotExport: \(error)\n", stderr)
            exit(1)
        }
    }
}
