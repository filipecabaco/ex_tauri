// ExTauriNative: the Swift side of ExTauri.Native, a channel between a native
// plugin and the BEAM running inside this app.
//
// Written by ex_tauri (`mix ex_tauri.ios plugin`), and rewritten by
// `mix ex_tauri.ios init` to match the ex_tauri in use: do not edit it.
//
// The BEAM listens on loopback and writes its port and a per-launch token to
// Library/Application Support/ex_tauri/native.json in the app's container; this
// reads them, connects, and proves it holds the token. Messages are JSON, framed
// by a 4-byte big-endian length. The BEAM starts after the app does and iOS may
// restart the page, never the BEAM, so this reconnects on its own until `stop()`.

import Foundation
import Network

public final class ExTauriNative {
  /// The channel this end speaks on: what Elixir subscribes to and sends on.
  public let channel: String
  /// On the main queue, each time the BEAM accepts this end.
  public var onConnect: (() -> Void)?
  /// On the main queue, when the connection to the BEAM is lost.
  public var onDisconnect: (() -> Void)?

  private var handler: ((Any) -> Void)?
  private var connection: NWConnection?
  private var ready = false
  private var running = false
  private let queue = DispatchQueue(label: "ex_tauri.native")
  private static let maxFrame = 16 * 1024 * 1024

  public init(channel: String) {
    self.channel = channel
  }

  /// Where the BEAM leaves its port and token: the same path ExTauri.Native derives.
  public static var handoffPath: String {
    NSHomeDirectory() + "/Library/Application Support/ex_tauri/native.json"
  }

  /// Sets what to do with a message from Elixir (`ExTauri.Native.send/2`), on the main queue.
  public func on(_ handler: @escaping (Any) -> Void) {
    queue.async { self.handler = handler }
  }

  /// Starts connecting, and keeps reconnecting, to the BEAM.
  public func start() {
    queue.async {
      guard !self.running else { return }
      self.running = true
      self.connect()
    }
  }

  public func stop() {
    queue.async {
      self.running = false
      self.connection?.cancel()
    }
  }

  public var isConnected: Bool { queue.sync { ready } }

  /// Sends a JSON value (dictionary, array, string, number, bool) to Elixir, where
  /// subscribers get `{:ex_tauri_native, channel, value}`. Dropped while not connected.
  @discardableResult
  public func send(_ value: Any) -> Bool {
    guard JSONSerialization.isValidJSONObject(["data": value]) else { return false }
    queue.async {
      if self.ready { self.write(["channel": self.channel, "data": value]) }
    }
    return true
  }

  // MARK: - Connection (all on `queue`)

  private func connect() {
    guard running else { return }

    guard
      let raw = FileManager.default.contents(atPath: Self.handoffPath),
      let handoff = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any],
      let port = handoff["port"] as? Int,
      let token = handoff["token"] as? String,
      let endpointPort = NWEndpoint.Port(rawValue: UInt16(clamping: port))
    else {
      retry()
      return
    }

    let conn = NWConnection(host: "127.0.0.1", port: endpointPort, using: .tcp)
    connection = conn

    conn.stateUpdateHandler = { [weak self] state in
      guard let self = self else { return }
      switch state {
      case .ready:
        self.write(["auth": token, "channels": [self.channel]])
        self.readFrame(conn)
      case .waiting:
        // Refused: the BEAM is not listening yet, or the handoff is stale.
        conn.cancel()
      case .failed, .cancelled:
        self.lost(conn)
      default:
        break
      }
    }

    conn.start(queue: queue)
  }

  private func lost(_ conn: NWConnection) {
    guard conn === connection else { return }
    connection = nil

    if ready {
      ready = false
      let callback = onDisconnect
      DispatchQueue.main.async { callback?() }
    }

    retry()
  }

  private func retry() {
    queue.asyncAfter(deadline: .now() + 1) { [weak self] in self?.connect() }
  }

  private func write(_ object: [String: Any]) {
    guard let conn = connection, let body = try? JSONSerialization.data(withJSONObject: object) else { return }
    var frame = Data(capacity: body.count + 4)
    let length = UInt32(body.count)
    frame.append(contentsOf: [UInt8(length >> 24 & 0xff), UInt8(length >> 16 & 0xff), UInt8(length >> 8 & 0xff), UInt8(length & 0xff)])
    frame.append(body)
    conn.send(content: frame, completion: .contentProcessed { _ in })
  }

  private func readFrame(_ conn: NWConnection) {
    conn.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] header, _, _, error in
      guard let self = self, error == nil, let header = header, header.count == 4 else {
        conn.cancel()
        return
      }

      let length = header.reduce(0) { $0 << 8 | Int($1) }

      guard length > 0, length <= Self.maxFrame else {
        conn.cancel()
        return
      }

      conn.receive(minimumIncompleteLength: length, maximumLength: length) { body, _, _, error in
        guard error == nil, let body = body, body.count == length,
          let object = (try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed])) as? [String: Any]
        else {
          conn.cancel()
          return
        }

        self.handle(object)
        self.readFrame(conn)
      }
    }
  }

  private func handle(_ object: [String: Any]) {
    if object["ok"] as? Bool == true {
      ready = true
      let callback = onConnect
      DispatchQueue.main.async { callback?() }
    } else if object["channel"] as? String == channel, let data = object["data"] {
      let callback = handler
      DispatchQueue.main.async { callback?(data) }
    }
  }
}
