import AppKit
import Foundation

// MARK: - Guarded Media App Scripting (Never Relaunches a Quit App)
/// True only if the app is currently running and not already terminated.
func isAppRunning(_ bundleID: String) -> Bool {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains { !$0.isTerminated }
}

/// Runs AppleScript against a media app ONLY if it is running.
/// A plain `tell application "X"` silently relaunches X if it has quit (or is in the middle of quitting),
/// which made Spotify / Music impossible to close. The `is running` check happens inside the same
/// script, right before the Apple Event is sent, so the race window is effectively closed.
func runGuardedAppScript(bundleID: String, appName: String, body: String, fallback: String = "OFFLINE") -> String {
    guard isAppRunning(bundleID) else { return fallback }
    let sc = """
    if application id "\(bundleID)" is running then
        tell application "\(appName)"
            \(body)
        end tell
    end if
    return "\(fallback)"
    """
    return runScript(sc)
}

// MARK: - Spotify Artwork Resolver (Public oEmbed, Zero AppleScript)
enum SpotifyArtworkResolver {
    private static var cache: [String: String] = [:] // main thread only

    /// Resolves album art for a `spotify:track:<id>` URI without talking to the Spotify app.
    static func resolve(trackURI: String, completion: @escaping (String?) -> Void) {
        let parts = trackURI.split(separator: ":")
        guard parts.count >= 3, parts[1] == "track" else { completion(nil); return }
        let id = String(parts[2])
        if let cached = cache[id] { completion(cached); return }
        guard let url = URL(string: "https://open.spotify.com/oembed?url=https://open.spotify.com/track/\(id)") else {
            completion(nil); return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            var thumb: String?
            if let data = data,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                thumb = obj["thumbnail_url"] as? String
            }
            DispatchQueue.main.async {
                if let t = thumb { cache[id] = t }
                completion(thumb)
            }
        }.resume()
    }
}

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
