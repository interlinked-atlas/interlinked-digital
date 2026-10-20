import Foundation

// TITAN MEMORY™ Realtime — Supabase postgres_changes subscription.
//
// Maintains a live WebSocket connection to the Supabase Realtime service.
// Listens for INSERT / UPDATE / DELETE on public.titan_memory and calls
// back into TitanMemory.shared to apply the delta in memory.
//
// Failure is always silent — installation is never blocked by this path.
// On disconnect, reconnects with exponential backoff and triggers
// syncFromCloud() to recover any events missed during the outage.

final class TitanMemoryRealtime: NSObject {

    static let shared = TitanMemoryRealtime()
    private override init() {}

    // MARK: - Configuration

    private let host    = "bmbmzytnpsntgzmutikp.supabase.co"
    private let channel = "realtime:public:titan_memory"

    private var wsURL: URL? {
        URL(string: "wss://\(host)/realtime/v1/websocket"
            + "?apikey=\(SupabaseConfig.anonKey)&vsn=1.0.0")
    }

    // MARK: - State

    private var task:           URLSessionWebSocketTask?
    private var heartbeatTask:  Task<Void, Never>?
    private var receiveTask:    Task<Void, Never>?
    private var reconnectTask:  Task<Void, Never>?
    private var started         = false
    private var ref             = 0       // monotonic Phoenix message ref

    // Backoff: 1 2 4 8 16 32 60 60 60 … seconds
    private var backoffIndex    = 0
    private let backoffSeconds  = [1, 2, 4, 8, 16, 32, 60]

    // MARK: - Public entry point

    func start() {
        guard !started else { return }
        started = true
        NSLog("[TitanRealtime] Starting live TITAN MEMORY™ sync")
        connect()
    }

    // MARK: - Connection

    private func connect() {
        guard let url = wsURL else {
            NSLog("[TitanRealtime] Invalid Realtime URL — live sync disabled")
            return
        }

        let session = URLSession(configuration: .default)
        let t = session.webSocketTask(with: url)
        task = t
        t.resume()

        receiveTask = Task.detached(priority: .background) { [weak self] in
            await self?.receiveLoop()
        }

        heartbeatTask = Task.detached(priority: .background) { [weak self] in
            await self?.heartbeatLoop()
        }

        sendJoin()
    }

    private func disconnect() {
        heartbeatTask?.cancel()
        receiveTask?.cancel()
        heartbeatTask = nil
        receiveTask   = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    // MARK: - Phoenix join

    private func sendJoin() {
        let r = nextRef()
        let msg: [String: Any] = [
            "event":    "phx_join",
            "topic":    channel,
            "payload": [
                "config": [
                    "broadcast":        ["self": false],
                    "presence":         ["key": ""],
                    "postgres_changes": [
                        ["event": "*", "schema": "public", "table": "titan_memory"]
                    ]
                ]
            ],
            "ref":      r,
            "join_ref": r
        ]
        send(msg)
    }

    // MARK: - Heartbeat loop (25s interval)

    private func heartbeatLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            guard !Task.isCancelled else { return }
            let msg: [String: Any] = [
                "event":    "heartbeat",
                "topic":    "phoenix",
                "payload":  [String: Any](),
                "ref":      nextRef(),
                "join_ref": NSNull()
            ]
            send(msg)
        }
    }

    // MARK: - Receive loop

    private func receiveLoop() async {
        guard let t = task else { return }
        while !Task.isCancelled {
            do {
                let message = try await t.receive()
                switch message {
                case .string(let text):
                    handleFrame(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleFrame(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                guard !Task.isCancelled else { return }
                NSLog("[TitanRealtime] Receive error — %@", error.localizedDescription)
                scheduleReconnect()
                return
            }
        }
    }

    // MARK: - Frame handling

    private func handleFrame(_ text: String) {
        guard let data  = text.data(using: .utf8),
              let obj   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = obj["event"] as? String else { return }

        switch event {
        case "phx_reply":
            // Log subscription confirmation
            if let payload = obj["payload"] as? [String: Any],
               let status  = payload["status"] as? String {
                if status == "ok" {
                    NSLog("[TitanRealtime] Subscribed to titan_memory")
                    backoffIndex = 0   // successful connection — reset backoff
                } else {
                    NSLog("[TitanRealtime] Join reply non-ok status: %@", status)
                }
            }

        case "postgres_changes":
            guard let payload  = obj["payload"] as? [String: Any],
                  let data     = payload["data"]  as? [String: Any],
                  let eventType = data["type"] as? String else { return }

            switch eventType {
            case "INSERT", "UPDATE":
                guard let newRow = data["record"] as? [String: Any], !newRow.isEmpty else { return }
                TitanMemory.shared.applyCloudEvent(row: newRow)
                NSLog("[TitanRealtime] Applied %@ for product: %@",
                      eventType, newRow["product_name"] as? String ?? "unknown")

            case "DELETE":
                guard let oldRow = data["old_record"] as? [String: Any],
                      let id     = oldRow["id"]  as? String else { return }
                TitanMemory.shared.removeEntry(id: id)
                NSLog("[TitanRealtime] Removed deleted entry id: %@", id)

            default:
                break
            }

        case "phx_error":
            NSLog("[TitanRealtime] phx_error received — scheduling reconnect")
            scheduleReconnect()

        case "phx_close":
            NSLog("[TitanRealtime] Channel closed — scheduling reconnect")
            scheduleReconnect()

        case "system":
            if let payload = obj["payload"] as? [String: Any],
               let msg     = payload["message"] as? String {
                NSLog("[TitanRealtime] System: %@", msg)
            }

        default:
            break
        }
    }

    // MARK: - Send

    private func send(_ payload: [String: Any]) {
        guard let t    = task,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        t.send(.string(text)) { error in
            if let error {
                NSLog("[TitanRealtime] Send error — %@", error.localizedDescription)
            }
        }
    }

    // MARK: - Reconnect

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        disconnect()

        let delay = backoffSeconds[min(backoffIndex, backoffSeconds.count - 1)]
        backoffIndex = min(backoffIndex + 1, backoffSeconds.count - 1)
        NSLog("[TitanRealtime] Reconnecting in %ds (attempt %d)", delay, backoffIndex)

        reconnectTask = Task.detached(priority: .background) { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            // Re-fetch full table state to repair any missed events
            TitanMemory.shared.syncFromCloud()
            self.connect()
        }
    }

    // MARK: - Helpers

    private func nextRef() -> String {
        ref += 1
        return "\(ref)"
    }
}
