import CryptoKit
import Foundation

private enum ExportError: Error, CustomStringConvertible {
    case usage
    case unsupportedSnapshot
    case unsafeDirectory
    case existingOutputMismatch

    var description: String {
        switch self {
        case .usage:
            return "Usage: SnapshotExport <snapshot.z80> (run from repository root)"
        case .unsupportedSnapshot:
            return "Only flat ZX Spectrum 48K snapshots with 49152 RAM bytes are supported"
        case .unsafeDirectory:
            return "Run from the repository root with an ignored, non-symlink private directory"
        case .existingOutputMismatch:
            return "An existing RAM export has the same filename but different contents"
        }
    }
}

private func sha256(_ bytes: [UInt8]) -> String {
    SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
}

@main
private struct SnapshotExport {
    static func main() {
        do {
            guard CommandLine.arguments.count == 2 else { throw ExportError.usage }
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
            if FileManager.default.fileExists(atPath: output.path) {
                let previous = try Data(contentsOf: output)
                guard previous == bytes else { throw ExportError.existingOutputMismatch }
            } else {
                try bytes.write(to: output, options: [.atomic])
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600], ofItemAtPath: output.path
                )
            }
            print(
                "snapshot_sha256=\(sha256(input)) ram_sha256=\(sha256(snapshot.ram48)) "
                    + "ram_bytes=\(snapshot.ram48.count) private_output=\(output.path)"
            )
        } catch {
            fputs("SnapshotExport: \(error)\n", stderr)
            exit(1)
        }
    }
}
