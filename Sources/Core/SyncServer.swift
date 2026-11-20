import AppKit
import Foundation
import Network
import Security

// MARK: - Authenticated Local HTTP & Optional Cloud Gist Sync Server
final class TutuSyncServer {
    static let shared = TutuSyncServer()

    private var listener: NWListener?
    private var cloudTimer: Timer?
    private var isSleeping = false

    // All mutable sync metadata is isolated to `stateQueue` to prevent data races.
    private let stateQueue = DispatchQueue(label: "com.customER.sync.state")
    private let netQueue = DispatchQueue(label: "com.customER.sync.network", qos: .utility)

    private var _syncVersion: Int = 1
    private var _lastAppliedPhoneVersion: Int = -1
    private var _lastEtag: String = ""

    private static let apiTokenAccount = "sync.lan.api_token"
    private static let gistIdAccount = "sync.github.gist_id"
    private static let gistTokenAccount = "sync.github.gist_token"

    /// Random 32-char hex token required on all LAN API requests (`/api/state`, `/api/mutate`).
    lazy var apiToken: String = {
        if let existing = KeychainHelper.load(account: Self.apiTokenAccount), !existing.isEmpty {
            return existing
        }
        if let fallback = UserDefaults.standard.string(forKey: "customer_lan_api_token"), !fallback.isEmpty {
            _ = KeychainHelper.save(fallback, account: Self.apiTokenAccount)
            return fallback
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        if !KeychainHelper.save(token, account: Self.apiTokenAccount) {
            UserDefaults.standard.set(token, forKey: "customer_lan_api_token")
        }
        return token
    }()

    /// Optional cloud sync credentials loaded exclusively from macOS Keychain or local `sync.json`
    /// (`~/Library/Application Support/CustomER/sync.json`). Never hardcoded in source.
    private func loadCloudConfig() -> (gistId: String, token: String)? {
        if let id = KeychainHelper.load(account: Self.gistIdAccount), !id.isEmpty,
           let tok = KeychainHelper.load(account: Self.gistTokenAccount), !tok.isEmpty {
            return (id, tok)
        }
        let fileURL = AppPaths.file("sync.json")
        if let data = try? Data(contentsOf: fileURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let id = json["gist_id"]?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty,
           let tok = json["github_token"]?.trimmingCharacters(in: .whitespacesAndNewlines), !tok.isEmpty {
            if KeychainHelper.save(id, account: Self.gistIdAccount),
               KeychainHelper.save(tok, account: Self.gistTokenAccount) {
                try? FileManager.default.removeItem(at: fileURL)
            }
            return (id, tok)
        }
        return nil
    }

    func getLanIP() -> String {
        var address = "127.0.0.1"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr {
            for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
                let interface = ptr.pointee
                guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                    let candidate = String(cString: hostname)
                    if !candidate.isEmpty && !candidate.hasPrefix("127.") {
                        address = candidate
                        break
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        return address
    }

    func pairingURL() -> String {
        if let cloudUrl = UserDefaults.standard.string(forKey: "tutu_apk_cloud_url"), !cloudUrl.isEmpty {
            return cloudUrl
        }
        let ip = getLanIP()
        return "http://\(ip):4321/?token=\(apiToken)"
    }

    func start() {
        if listener == nil {
            do {
                let params = NWParameters.tcp
                params.allowLocalEndpointReuse = true
                let nwListener = try NWListener(using: params, on: 4321)
                nwListener.newConnectionHandler = { [weak self] conn in
                    self?.handleConnection(conn)
                }
                nwListener.start(queue: netQueue)
                listener = nwListener
            } catch {
                // Port already in use
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(onWillSleep), name: NSWorkspace.willSleepNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(onDidWake), name: NSWorkspace.didWakeNotification, object: nil
        )

        startCloudTimerIfConfigured()
    }

    @objc private func onWillSleep() {
        isSleeping = true
    }

    @objc private func onDidWake() {
        isSleeping = false
        if loadCloudConfig() != nil {
            pullStateFromCloud()
        }
    }

    private func startCloudTimerIfConfigured() {
        guard cloudTimer == nil, loadCloudConfig() != nil else { return }
        pushStateToCloud()
        // 15s polling with ETag + sleep pause avoids GitHub rate limits and battery drain.
        cloudTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            guard let self = self, !self.isSleeping else { return }
            self.pullStateFromCloud()
        }
    }

    func pushStateToCloud() {
        guard let cfg = loadCloudConfig() else { return }
        DispatchQueue.main.async {
            let version: Int = self.stateQueue.sync {
                self._syncVersion += 1
                return self._syncVersion
            }
            let stateData = self.buildStateJSON(source: "mac", version: version)
            guard let stateStr = String(data: stateData, encoding: .utf8),
                  let url = URL(string: "https://api.github.com/gists/\(cfg.gistId)") else { return }

            let bodyObj: [String: Any] = [
                "files": [
                    "tututodo_state.json": ["content": stateStr]
                ]
            ]
            guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj) else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "PATCH"
            req.setValue("Bearer \(cfg.token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("CustomER-mac", forHTTPHeaderField: "User-Agent")
            req.httpBody = bodyData
            req.timeoutInterval = 8.0
            URLSession.shared.dataTask(with: req).resume()
        }
    }

    private func pullStateFromCloud() {
        guard let cfg = loadCloudConfig(),
              let url = URL(string: "https://api.github.com/gists/\(cfg.gistId)") else { return }

        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("Bearer \(cfg.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("CustomER-mac", forHTTPHeaderField: "User-Agent")
        let etag = stateQueue.sync { _lastEtag }
        if !etag.isEmpty {
            req.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        req.timeoutInterval = 6.0

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            guard let self = self, error == nil,
                  let httpResp = response as? HTTPURLResponse else { return }
            if httpResp.statusCode == 304 { return }
            if let newEtag = httpResp.value(forHTTPHeaderField: "ETag") {
                self.stateQueue.async { self._lastEtag = newEtag }
            }
            guard let data = data,
                  let gistJson = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let files = gistJson["files"] as? [String: Any],
                  let fileObj = files["tututodo_state.json"] as? [String: Any],
                  let contentStr = fileObj["content"] as? String,
                  let contentData = contentStr.data(using: .utf8),
                  let json = (try? JSONSerialization.jsonObject(with: contentData)) as? [String: Any] else { return }

            let source = (json["source"] as? String) ?? ""
            let version = (json["version"] as? Int) ?? 0
            guard source == "phone",
                  let rawReminders = json["reminders"] as? [[String: Any]] else { return }

            let shouldApply: Bool = self.stateQueue.sync {
                guard version != self._lastAppliedPhoneVersion else { return false }
                self._lastAppliedPhoneVersion = version
                self._syncVersion = max(self._syncVersion, version)
                return true
            }
            guard shouldApply else { return }

            var parsed: [Reminder] = []
            for item in rawReminders {
                guard let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !title.isEmpty else { continue }
                var r = Reminder(title: title)
                if let idStr = item["id"] as? String, let uuid = UUID(uuidString: idStr) { r.id = uuid }
                r.isCompleted = (item["isCompleted"] as? Bool) ?? false
                r.isStarred = (item["isStarred"] as? Bool) ?? false
                r.isDeleted = (item["isDeleted"] as? Bool) ?? false
                if let created = item["createdAt"] as? Double {
                    r.createdAt = Date(timeIntervalSinceReferenceDate: created)
                }
                if let updated = item["updatedAt"] as? Double {
                    r.updatedAt = updated
                }
                parsed.append(r)
            }
            DispatchQueue.main.async {
                ReminderStore.shared.mergeFromRemote(parsed)
                NotificationCenter.default.post(name: NSNotification.Name("com.user.tututodo.reload"), object: nil)
            }
        }.resume()
    }

    // MARK: - Embedded Local HTTP Server
    private func handleConnection(_ conn: NWConnection) {
        conn.start(queue: netQueue)
        receiveFullRequest(conn: conn, accumulated: Data())
    }

    private func receiveFullRequest(conn: NWConnection, accumulated: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { conn.cancel(); return }
            var buffer = accumulated
            if let d = data { buffer.append(d) }
            if let sepRange = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buffer.subdata(in: 0..<sepRange.lowerBound)
                let bodyData = buffer.subdata(in: sepRange.upperBound..<buffer.count)
                let headerStr = String(data: headerData, encoding: .utf8) ?? ""
                var contentLength = 0
                for line in headerStr.components(separatedBy: "\r\n") {
                    if line.lowercased().hasPrefix("content-length:") {
                        let val = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                        contentLength = min(Int(val) ?? 0, 512 * 1024)
                    }
                }
                if bodyData.count < contentLength && !isComplete && error == nil {
                    self.receiveFullRequest(conn: conn, accumulated: buffer)
                    return
                }
                self.routeRequest(conn: conn, headerStr: headerStr, bodyData: bodyData)
            } else if !isComplete && error == nil && buffer.count < 65536 {
                self.receiveFullRequest(conn: conn, accumulated: buffer)
            } else {
                conn.cancel()
            }
        }
    }

    private func extractHeaders(_ headerStr: String) -> [String: String] {
        var headers: [String: String] = [:]
        for line in headerStr.components(separatedBy: "\r\n").dropFirst() {
            if let idx = line.firstIndex(of: ":") {
                let key = line[..<idx].trimmingCharacters(in: .whitespaces).lowercased()
                let val = line[line.index(after: idx)...].trimmingCharacters(in: .whitespaces)
                headers[key] = val
            }
        }
        return headers
    }

    private func queryParam(_ name: String, in rawPath: String) -> String? {
        guard let comps = URLComponents(string: "http://localhost\(rawPath)"),
              let items = comps.queryItems else { return nil }
        return items.first(where: { $0.name == name })?.value
    }

    private func isAuthorized(headers: [String: String], rawPath: String) -> Bool {
        if let auth = headers["authorization"], auth.hasPrefix("Bearer ") {
            let candidate = String(auth.dropFirst("Bearer ".count)).trimmingCharacters(in: .whitespaces)
            if constantTimeEquals(candidate, apiToken) { return true }
        }
        if let hdrToken = headers["x-sync-token"], constantTimeEquals(hdrToken, apiToken) {
            return true
        }
        if let qToken = queryParam("token", in: rawPath), constantTimeEquals(qToken, apiToken) {
            return true
        }
        return false
    }

    private func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let ab = Array(a.utf8), bb = Array(b.utf8)
        guard ab.count == bb.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<ab.count { diff |= ab[i] ^ bb[i] }
        return diff == 0
    }

    private func buildStateJSON(source: String = "mac", version: Int = 1) -> Data {
        let remindersArray: [[String: Any]] = ReminderStore.shared.allRecords.map { r in
            [
                "id": r.id.uuidString.uppercased(),
                "title": r.title,
                "isCompleted": r.isCompleted,
                "isStarred": r.isStarred,
                "isDeleted": r.isDeleted,
                "createdAt": r.createdAt.timeIntervalSinceReferenceDate,
                "updatedAt": r.updatedAt
            ]
        }
        let payload: [String: Any] = [
            "source": source,
            "version": version,
            "updatedAt": Date().timeIntervalSince1970,
            "themeMode": "customer-live",
            "customerLiveTheme": [
                "preset": ThemeManager.shared.currentPreset.rawValue,
                "bgColor": ThemeManager.shared.currentBgColor.toHex(),
                "textColor": ThemeManager.shared.currentTextColor.toHex(),
                "accentColor": ThemeManager.shared.currentAccentColor.toHex(),
                "fontName": ThemeManager.shared.customFontName ?? "Menlo"
            ],
            "reminders": remindersArray
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
    }

    private func routeRequest(conn: NWConnection, headerStr: String, bodyData: Data) {
        let firstLine = headerStr.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { conn.cancel(); return }
        let method = parts[0].uppercased()
        let rawPath = parts[1]
        let pathOnly = rawPath.components(separatedBy: "?").first ?? "/"
        let headers = extractHeaders(headerStr)

        if method == "OPTIONS" {
            sendResponse(conn: conn, status: "204 No Content", contentType: "text/plain", body: Data())
            return
        }

        if method == "GET" && (pathOnly == "/" || pathOnly == "/index.html") {
            sendResponse(conn: conn, status: "200 OK", contentType: "text/html; charset=utf-8", body: Data(Self.embeddedMobileHTML.utf8))
            return
        }

        // All /api/* endpoints require valid pairing token
        if pathOnly.hasPrefix("/api/") {
            guard isAuthorized(headers: headers, rawPath: rawPath) else {
                sendResponse(conn: conn, status: "401 Unauthorized", contentType: "application/json; charset=utf-8", body: Data("{\"error\":\"unauthorized\"}".utf8))
                return
            }
        }

        if method == "GET" && pathOnly == "/api/state" {
            DispatchQueue.main.async {
                let data = self.buildStateJSON()
                self.sendResponse(conn: conn, status: "200 OK", contentType: "application/json; charset=utf-8", body: data)
            }
            return
        }

        if method == "GET" && pathOnly == "/api/info" {
            let ip = getLanIP()
            let info: [String: Any] = ["lanIp": ip, "port": 4321, "phoneUrl": "http://\(ip):4321/"]
            let data = (try? JSONSerialization.data(withJSONObject: info)) ?? Data("{}".utf8)
            sendResponse(conn: conn, status: "200 OK", contentType: "application/json; charset=utf-8", body: data)
            return
        }

        if method == "POST" && pathOnly == "/api/mutate" {
            let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] ?? [:]
            let type = (json["type"] as? String) ?? ""
            DispatchQueue.main.async {
                let store = ReminderStore.shared
                switch type {
                case "ADD_REMINDER":
                    if let item = json["item"] as? [String: Any],
                       let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !title.isEmpty {
                        var rem = Reminder(title: title)
                        if let starred = item["isStarred"] as? Bool { rem.isStarred = starred }
                        store.add(rem)
                    }
                case "TOGGLE_REMINDER":
                    if let idStr = json["id"] as? String, let uuid = UUID(uuidString: idStr) { store.toggle(id: uuid) }
                case "TOGGLE_STAR":
                    if let idStr = json["id"] as? String, let uuid = UUID(uuidString: idStr) { store.toggleStar(id: uuid) }
                case "UPDATE_REMINDER":
                    if let idStr = json["id"] as? String, let uuid = UUID(uuidString: idStr),
                       let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !title.isEmpty { store.updateTitle(id: uuid, title: title) }
                case "DELETE_REMINDER":
                    if let idStr = json["id"] as? String, let uuid = UUID(uuidString: idStr) { store.delete(id: uuid) }
                case "CLEAR_COMPLETED":
                    store.clearCompleted()
                default:
                    break
                }
                NotificationCenter.default.post(name: NSNotification.Name("com.user.tututodo.reload"), object: nil)
                let stateData = self.buildStateJSON()
                var resp = Data("{\"ok\":true,\"state\":".utf8)
                resp.append(stateData)
                resp.append(Data("}".utf8))
                self.sendResponse(conn: conn, status: "200 OK", contentType: "application/json; charset=utf-8", body: resp)
            }
            return
        }

        sendResponse(conn: conn, status: "404 Not Found", contentType: "text/plain", body: Data("Not Found".utf8))
    }

    private func sendResponse(conn: NWConnection, status: String, contentType: String, extraHeaders: String = "", body: Data) {
        // Strict same-origin policy (no wildcard CORS) to block cross-site requests from browsers.
        let header = "HTTP/1.1 \(status)\r\n" +
                     "Content-Type: \(contentType)\r\n" +
                     "Content-Length: \(body.count)\r\n" +
                     "X-Content-Type-Options: nosniff\r\n" +
                     "Cache-Control: no-store\r\n" +
                     extraHeaders +
                     "Connection: close\r\n\r\n"
        var payload = Data(header.utf8)
        payload.append(body)
        conn.send(content: payload, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    private static let embeddedMobileHTML = """
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no" />
<meta name="theme-color" id="metaTheme" content="#FEF9C3" />
<title>CustomER Tasks</title>
<style>
:root {
  --bg: #FEF9C3;
  --surface: #FEFCE8;
  --text: #800020;
  --add-bg: #800020;
  --add-text: #FEFCE8;
  --border: #000000;
  --dim: #595940;
  --font: Menlo, monospace, sans-serif;
}
* { box-sizing: border-box; margin: 0; padding: 0; -webkit-tap-highlight-color: transparent; }
body { background: var(--bg); color: var(--text); font-family: var(--font); min-height: 100dvh; padding: 14px; display: flex; flex-direction: column; }
.bar { display: flex; align-items: center; justify-content: space-between; margin-bottom: 10px; }
.title-wrap { display: flex; align-items: center; gap: 8px; }
h1 { font-size: 18px; font-weight: 700; }
.badge { background: var(--surface); color: var(--text); border: 1px solid var(--border); font-size: 11px; font-weight: 700; padding: 2px 7px; }
.btn { background: var(--surface); color: var(--text); border: 1px solid var(--border); font-family: var(--font); font-size: 12px; font-weight: 700; padding: 6px 12px; cursor: pointer; }
.btn-primary { background: var(--add-bg); color: var(--add-text); }
.tabs { display: grid; grid-template-columns: 1fr 1fr; margin-bottom: 10px; }
.tab { background: transparent; color: var(--text); border: 1px solid var(--border); font-family: var(--font); font-size: 12px; padding: 6px; cursor: pointer; }
.tab.active { background: var(--surface); font-weight: 700; }
.list { flex: 1; display: flex; flex-direction: column; gap: 5px; overflow-y: auto; }
.row { background: var(--surface); display: flex; align-items: center; gap: 8px; padding: 8px 10px; min-height: 38px; }
.row.starred { border: 1.5px solid #F59E0B; }
.check { width: 20px; height: 20px; border: 1px solid var(--border); background: transparent; color: #FFFFFF; font-size: 11px; font-weight: 700; cursor: pointer; }
.row.done .check { background: var(--border); }
.row-title { flex: 1; font-size: 13px; font-weight: 500; word-break: break-word; cursor: pointer; }
.row.starred .row-title { color: #F59E0B; font-weight: 700; }
.row.done .row-title { color: var(--dim); text-decoration: line-through; }
.star, .del { width: 24px; height: 24px; border: 1px solid var(--border); background: transparent; color: var(--dim); font-size: 12px; font-weight: 700; cursor: pointer; }
.row.starred .star { background: #F59E0B; border-color: #D97706; color: #FFFFFF; }
.del { border: none; }
.footer { display: flex; align-items: center; justify-content: space-between; margin-top: 10px; padding-top: 6px; font-size: 11px; }
.link-btn { background: none; border: none; color: var(--text); font-family: var(--font); font-size: 11px; cursor: pointer; }
.status { color: var(--dim); font-size: 10px; }
.modal { position: fixed; inset: 0; background: rgba(0,0,0,0.65); display: flex; align-items: center; justify-content: center; padding: 16px; }
.modal[hidden] { display: none; }
.panel { width: 100%; max-width: 340px; background: var(--bg); border: 1px solid var(--border); padding: 14px; }
.input { width: 100%; background: var(--surface); color: var(--text); border: 1px solid var(--border); font-family: var(--font); font-size: 14px; font-weight: 700; padding: 8px 10px; margin-bottom: 12px; outline: none; }
.actions { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
</style>
</head>
<body>
<div class="bar">
  <div class="title-wrap">
    <h1>tututodo</h1>
    <span class="badge" id="badge">0</span>
  </div>
  <button class="btn btn-primary" id="addOpenBtn" type="button">+ Add</button>
</div>
<div class="tabs">
  <button class="tab active" id="tabActive" type="button">Active</button>
  <button class="tab" id="tabDone" type="button">Done</button>
</div>
<div class="list" id="list"></div>
<div class="footer">
  <button class="link-btn" id="clearBtn" type="button">Clear Done</button>
  <span class="status" id="status">Live</span>
</div>
<div class="modal" id="modal" hidden>
  <form class="panel" id="form">
    <input class="input" id="input" type="text" placeholder="What to do?" autocomplete="off" />
    <div class="actions">
      <button class="btn" id="cancelBtn" type="button">Cancel</button>
      <button class="btn btn-primary" id="saveBtn" type="submit">Add</button>
    </div>
  </form>
</div>
<script>
(() => {
  const params = new URLSearchParams(window.location.search);
  if (params.get('token')) {
    localStorage.setItem('customer_api_token', params.get('token'));
    window.history.replaceState({}, '', '/');
  }
  const getToken = () => localStorage.getItem('customer_api_token') || '';
  const authHeaders = () => ({ 'Authorization': 'Bearer ' + getToken() });

  let state = { reminders: [], customerLiveTheme: null };
  let tab = 0;
  let editId = null;
  try {
    const cached = JSON.parse(localStorage.getItem('tutu_state') || 'null');
    if (cached && Array.isArray(cached.reminders)) state = cached;
  } catch (_) {}

  const listEl = document.getElementById('list');
  const badgeEl = document.getElementById('badge');
  const statusEl = document.getElementById('status');
  const modal = document.getElementById('modal');
  const form = document.getElementById('form');
  const input = document.getElementById('input');
  const saveBtn = document.getElementById('saveBtn');

  document.getElementById('tabActive').onclick = () => { tab = 0; render(); };
  document.getElementById('tabDone').onclick = () => { tab = 1; render(); };
  document.getElementById('addOpenBtn').onclick = () => openModal(null);
  document.getElementById('cancelBtn').onclick = () => { modal.hidden = true; };
  document.getElementById('clearBtn').onclick = () => mutate({ type: 'CLEAR_COMPLETED' });

  function openModal(item) {
    editId = item ? item.id : null;
    input.value = item ? item.title : '';
    saveBtn.textContent = item ? 'Save' : 'Add';
    modal.hidden = false;
    setTimeout(() => input.focus(), 20);
  }

  form.onsubmit = (e) => {
    e.preventDefault();
    const title = input.value.trim();
    if (!title) return;
    modal.hidden = true;
    if (editId) mutate({ type: 'UPDATE_REMINDER', id: editId, title });
    else mutate({ type: 'ADD_REMINDER', item: { title, isStarred: false } });
  };

  function applyTheme(t) {
    if (!t) return;
    const r = document.documentElement.style;
    if (t.bgColor) { r.setProperty('--bg', t.bgColor); document.getElementById('metaTheme').content = t.bgColor; }
    if (t.textColor) r.setProperty('--text', t.textColor);
    if (t.fontName) r.setProperty('--font', `'${t.fontName}', monospace, sans-serif`);
  }

  function render() {
    applyTheme(state.customerLiveTheme);
    const items = (Array.isArray(state.reminders) ? state.reminders : []).filter(i => !i.isDeleted);
    const activeCount = items.filter(i => !i.isCompleted).length;
    badgeEl.textContent = activeCount;
    badgeEl.style.display = activeCount ? 'inline-block' : 'none';
    document.getElementById('tabActive').classList.toggle('active', tab === 0);
    document.getElementById('tabDone').classList.toggle('active', tab === 1);

    const filtered = items
      .filter(i => tab === 1 ? i.isCompleted : !i.isCompleted)
      .sort((a, b) => (a.isStarred !== b.isStarred) ? (a.isStarred ? -1 : 1) : ((b.createdAt || 0) - (a.createdAt || 0)));

    listEl.innerHTML = '';
    for (const item of filtered) {
      const row = document.createElement('div');
      row.className = 'row' + (item.isCompleted ? ' done' : '') + (item.isStarred ? ' starred' : '');

      const check = document.createElement('button');
      check.className = 'check';
      check.textContent = item.isCompleted ? 'v' : '';
      check.onclick = () => mutate({ type: 'TOGGLE_REMINDER', id: item.id });

      const title = document.createElement('div');
      title.className = 'row-title';
      title.textContent = item.title;
      title.onclick = () => openModal(item);

      const star = document.createElement('button');
      star.className = 'star';
      star.textContent = '*';
      star.onclick = () => mutate({ type: 'TOGGLE_STAR', id: item.id });

      const del = document.createElement('button');
      del.className = 'del';
      del.textContent = 'x';
      del.onclick = () => mutate({ type: 'DELETE_REMINDER', id: item.id });

      row.append(check, title, star, del);
      listEl.appendChild(row);
    }
  }

  async function pull() {
    if (document.visibilityState === 'hidden') return;
    try {
      const res = await fetch('/api/state', { cache: 'no-store', headers: authHeaders() });
      if (res.status === 401) { statusEl.textContent = 'Rescan QR'; return; }
      const data = await res.json();
      if (data && Array.isArray(data.reminders)) {
        state = data;
        localStorage.setItem('tutu_state', JSON.stringify(state));
        statusEl.textContent = 'Synced';
        render();
      }
    } catch (_) {
      statusEl.textContent = 'Offline';
    }
  }

  async function mutate(payload) {
    try {
      const res = await fetch('/api/mutate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...authHeaders() },
        body: JSON.stringify(payload)
      });
      const json = await res.json();
      if (json.ok && json.state) {
        state = json.state;
        localStorage.setItem('tutu_state', JSON.stringify(state));
        statusEl.textContent = 'Synced';
        render();
      }
    } catch (_) {
      statusEl.textContent = 'Offline';
    }
  }

  render();
  pull();
  setInterval(pull, 5000);
  document.addEventListener('visibilitychange', pull);
})();
</script>
</body>
</html>
"""
}
