import Foundation

/// Runs the bundled `roblox-bootstrapper` script. The app is only a front end:
/// installing, updating, FastFlags and mods all go through the script so the
/// CLI and the GUI always behave the same.
enum ScriptRunner {
    struct Result {
        let status: Int32
        let output: String
        let errorOutput: String

        var succeeded: Bool { status == 0 }

        /// The script reports failures as `error: <message>` on stderr.
        var errorMessage: String? {
            let lines = errorOutput.split(separator: "\n").map(String.init)
            if let line = lines.last(where: { $0.hasPrefix("error: ") }) {
                return String(line.dropFirst("error: ".count))
            }
            return lines.last
        }
    }

    static var scriptPath: String {
        if let bundled = Bundle.main.path(forResource: "roblox-bootstrapper", ofType: nil) {
            return bundled
        }
        return NSHomeDirectory() + "/.local/bin/roblox-bootstrapper"
    }

    private final class Box {
        var data = Data()
    }

    /// Runs the script with `args`. `onLine` gets each stdout line and
    /// `completion` the result, both on the main queue.
    @discardableResult
    static func run(
        _ args: [String],
        onLine: ((String) -> Void)? = nil,
        completion: ((Result) -> Void)? = nil
    ) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath] + args
        var env = ProcessInfo.processInfo.environment
        env["ROBLOX_BOOTSTRAPPER_GUI"] = "1"
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = env
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try process.run()
            } catch {
                DispatchQueue.main.async {
                    completion?(Result(status: -1, output: "", errorOutput: "error: \(error.localizedDescription)"))
                }
                return
            }

            let errBox = Box()
            let errDone = DispatchGroup()
            errDone.enter()
            DispatchQueue.global().async {
                errBox.data = err.fileHandleForReading.readDataToEndOfFile()
                errDone.leave()
            }

            var all = Data()
            var pending = Data()
            let handle = out.fileHandleForReading
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                all.append(chunk)
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 0x0A) {
                    let line = String(decoding: pending[pending.startIndex..<newline], as: UTF8.self)
                    pending.removeSubrange(pending.startIndex...newline)
                    if let onLine {
                        DispatchQueue.main.async { onLine(line) }
                    }
                }
            }
            process.waitUntilExit()
            errDone.wait()

            let result = Result(
                status: process.terminationStatus,
                output: String(decoding: all, as: UTF8.self),
                errorOutput: String(decoding: errBox.data, as: UTF8.self)
            )
            DispatchQueue.main.async { completion?(result) }
        }
        return process
    }
}

struct BootstrapperStatus: Decodable {
    let version: String
    let installPath: String
    let installDir: String
    let channel: String
    let arch: String
    let archSetting: String
    let installed: String?
    let installedHash: String?
    let latest: String?
    let latestHash: String?
    let upToDate: Bool?
    let running: Bool
    let handlerInstalled: Bool
    let fflagsPath: String
    let modsPath: String
    let supportPath: String
    let logPath: String
}
