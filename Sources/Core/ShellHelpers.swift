import Foundation

// MARK: - AppleScript, Shell & Safe KVC Helpers
func runScript(_ code: String) -> String {
    let proc = Process()
    let pipe = Pipe()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    proc.arguments = ["-e", code]
    proc.standardOutput = pipe
    proc.standardError = Pipe()
    do {
        try proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    } catch {
        return ""
    }
}

func shellRun(_ command: String) -> String {
    let proc = Process()
    let pipe = Pipe()
    proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
    proc.arguments = ["-c", "export PATH=\"$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH\"; \(command)"]
    proc.standardOutput = pipe
    proc.standardError = pipe
    do {
        try proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    } catch {
        return ""
    }
}

extension NSObject {
    func safeValue(forKey key: String) -> Any? {
        var count: UInt32 = 0
        guard let propList = class_copyPropertyList(type(of: self), &count) else { return nil }
        defer { free(propList) }
        for i in 0..<Int(count) {
            let prop = propList[i]
            if String(cString: property_getName(prop)) == key {
                return self.value(forKey: key)
            }
        }
        return nil
    }
}
