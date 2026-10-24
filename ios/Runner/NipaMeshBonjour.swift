import Flutter
import Foundation

/// Publishes this device and browses for the others as `_nipaplay-mesh._tcp`
/// through the system's Bonjour (no multicast entitlement, and the system is
/// what asks for the local network permission). The instance is named by the
/// device id, with `mesh=1`, `deviceId` and `port` in the TXT record, the same
/// service the desktop's own responder speaks. Peers found are reported to
/// Dart as `peer {deviceId, host, port, ttl}` per address; ttl 0 withdraws.
final class NipaMeshBonjour: NSObject, NetServiceDelegate, NetServiceBrowserDelegate {
  private let channel: FlutterMethodChannel
  private var published: NetService?
  private var browser: NetServiceBrowser?
  private var ownName = ""
  private var found: [String: NetService] = [:]
  private var reported: [String: (deviceId: String, hosts: [String], port: Int)] = [:]
  private var refresh: Timer?
  private let ttl = 120

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "nipaplay/mesh_bonjour", binaryMessenger: messenger)
    let bridge = NipaMeshBonjour(channel: channel)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "start":
        guard
          let args = call.arguments as? [String: Any],
          let deviceId = args["deviceId"] as? String,
          let port = args["port"] as? Int,
          let type = args["serviceType"] as? String
        else {
          result(FlutterError(code: "invalid_arguments", message: nil, details: nil))
          return
        }
        bridge.start(deviceId: deviceId, port: port, type: type)
        result(nil)
      case "stop":
        bridge.stop()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  private func start(deviceId: String, port: Int, type: String) {
    stop()
    ownName = deviceId
    let service = NetService(domain: "local.", type: type, name: deviceId, port: Int32(port))
    service.delegate = self
    service.setTXTRecord(
      NetService.data(fromTXTRecord: [
        "mesh": Data("1".utf8),
        "deviceId": Data(deviceId.utf8),
        "port": Data(String(port).utf8),
      ]))
    // The name is the device id: another owner of it is not renamed around.
    service.publish(options: [.noAutoRename])
    published = service
    let browser = NetServiceBrowser()
    browser.delegate = self
    browser.searchForServices(ofType: type, inDomain: "local.")
    self.browser = browser
    refresh = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
      guard let self = self else { return }
      for service in self.found.values { service.resolve(withTimeout: 5) }
    }
  }

  private func stop() {
    refresh?.invalidate()
    refresh = nil
    browser?.stop()
    browser = nil
    published?.stop()
    published = nil
    for service in found.values { service.stop() }
    found.removeAll()
    reported.removeAll()
  }

  // MARK: browsing

  func netServiceBrowser(
    _ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool
  ) {
    guard service.name != ownName, found[service.name] == nil else { return }
    service.delegate = self
    found[service.name] = service
    service.resolve(withTimeout: 5)
  }

  func netServiceBrowser(
    _ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool
  ) {
    found[service.name]?.stop()
    found.removeValue(forKey: service.name)
    withdraw(service.name)
  }

  func netServiceBrowser(
    _ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]
  ) {
    NSLog("[MeshBonjour] browse failed: \(errorDict)")
  }

  func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
    NSLog("[MeshBonjour] publish failed: \(errorDict)")
  }

  func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
    NSLog("[MeshBonjour] resolve \(sender.name) failed: \(errorDict)")
  }

  func netServiceDidResolveAddress(_ sender: NetService) {
    var deviceId = sender.name
    if let data = sender.txtRecordData() {
      let txt = NetService.dictionary(fromTXTRecord: data)
      if let value = txt["deviceId"], let text = String(data: value, encoding: .utf8) {
        deviceId = text
      }
    }
    var hosts: [String] = []
    for address in sender.addresses ?? [] {
      if let host = Self.numericHost(address), !hosts.contains(host) { hosts.append(host) }
    }
    let port = sender.port
    guard port > 0 else { return }
    // An address that was reported before and is gone now is withdrawn.
    if let previous = reported[sender.name] {
      for host in previous.hosts where !hosts.contains(host) {
        send(deviceId: previous.deviceId, host: host, port: previous.port, ttl: 0)
      }
    }
    reported[sender.name] = (deviceId, hosts, port)
    for host in hosts { send(deviceId: deviceId, host: host, port: port, ttl: ttl) }
  }

  private func withdraw(_ name: String) {
    guard let previous = reported.removeValue(forKey: name) else { return }
    for host in previous.hosts {
      send(deviceId: previous.deviceId, host: host, port: previous.port, ttl: 0)
    }
  }

  private func send(deviceId: String, host: String, port: Int, ttl: Int) {
    channel.invokeMethod(
      "peer", arguments: ["deviceId": deviceId, "host": host, "port": port, "ttl": ttl])
  }

  /// A numeric address, without a scope: link-local ones mean nothing off
  /// the interface they were heard on and are left out.
  private static func numericHost(_ data: Data) -> String? {
    data.withUnsafeBytes { raw -> String? in
      guard let base = raw.baseAddress else { return nil }
      let sa = base.assumingMemoryBound(to: sockaddr.self)
      var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      let status = getnameinfo(
        sa, socklen_t(data.count), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST)
      guard status == 0 else { return nil }
      let host = String(cString: buffer)
      if host.hasPrefix("fe80") || host.hasPrefix("169.254.") || host.contains("%") {
        return nil
      }
      return host
    }
  }
}
