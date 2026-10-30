# erika_flutter (0.3.0, 0.3.1) performs open/seek synchronously on the platform thread.
# A Dart loopback media source then waits on the very thread opening it.
# Generate a build-local source copy; never mutate the shared pub cache.
module ErikaMediaIO
  def self.replace!(source, before, after)
    raise "Erika media I/O patch: upstream anchor changed: #{before.lines.first.strip}" unless source.scan(before).length == 1
    source.sub!(before, after)
  end

  def self.patch(source)
    source = source.dup
    replace!(source, "  func open(\n    uri: String,\n    httpHeaders: [String: String],",  <<~'SWIFT'.lines.map { |l| "  #{l}" }.join)
      // Main-thread gate: surface changes and commands must not wait on the
      // native lock while a worker waits for the Dart HTTP range server.
      private var mediaIOPending = false
      private var mediaIOWaiters: [() -> Void] = []

      func deferDuringMediaIO(_ work: @escaping () -> Void) -> Bool {
        guard mediaIOPending else { return false }
        mediaIOWaiters.append(work)
        return true
      }

      func beginMediaIO() { mediaIOPending = true }

      func endMediaIO() {
        mediaIOPending = false
        let waiting = mediaIOWaiters
        mediaIOWaiters.removeAll()
        for work in waiting { work() }
      }

      func prepareOpen(uri: String) {
        playbackState = 0
        positionSeconds = 0
        durationSeconds = nil
        positionUpdateTime = ProcessInfo.processInfo.systemUptime
        if nowPlayingTitle.isEmpty {
          let fallbackTitle = URL(string: uri)?.lastPathComponent.removingPercentEncoding
            ?? URL(fileURLWithPath: uri).lastPathComponent
          nowPlayingTitle = fallbackTitle.isEmpty ? "Erika" : fallbackTitle
        }
      }

      func open(
        uri: String,
        httpHeaders: [String: String],
    SWIFT
    before = <<~'SWIFT'.lines.map { |l| "    #{l}" }.join
      playbackState = 0
      positionSeconds = 0
      durationSeconds = nil
      positionUpdateTime = ProcessInfo.processInfo.systemUptime
      if nowPlayingTitle.isEmpty {
        let fallbackTitle = URL(string: uri)?.lastPathComponent.removingPercentEncoding
          ?? URL(fileURLWithPath: uri).lastPathComponent
        nowPlayingTitle = fallbackTitle.isEmpty ? "Erika" : fallbackTitle
      }
      try withNativeCall {
    SWIFT
    start = source.index("  func open(\n    uri: String,\n    httpHeaders:")
    tail = source[start..]
    replace!(tail, before, "    try withNativeCall {\n")
    source[start..] = tail
    replace!(source, "    onNowPlayingChanged?(self)\n  }\n\n  func play()", "  }\n\n  func play()")
    replace!(source, <<~'SWIFT'.lines.map { |l| "    #{l}" }.join, <<~'SWIFT'.lines.map { |l| "    #{l}" }.join)
      positionSeconds = Double(positionMicros) / 1_000_000
      positionUpdateTime = ProcessInfo.processInfo.systemUptime
      onNowPlayingChanged?(self)
    SWIFT
      DispatchQueue.main.async {
        self.positionSeconds = Double(positionMicros) / 1_000_000
        self.positionUpdateTime = ProcessInfo.processInfo.systemUptime
        self.onNowPlayingChanged?(self)
      }
    SWIFT
    replace!(source, '    do {\n      switch call.method {'.gsub('\\n', "\n"), <<~'SWIFT'.lines.map { |l| "    #{l}" }.join.rstrip)
      if let args = call.arguments as? [String: Any],
         let id = int64Value(args["playerId"]), let host = players[id],
         host.deferDuringMediaIO({ self.handle(call, result: result) }) {
        return
      }
      do {
        switch call.method {
    SWIFT
    replace!(source, <<~'SWIFT'.lines.map { |l| "        #{l}" }.join, <<~'SWIFT'.lines.map { |l| "        #{l}" }.join)
      try host.open(
        uri: uri,
        httpHeaders: headers,
        httpReadAheadBytes: readAhead,
        httpBackBufferBytes: backBuffer
      )
      result(nil)
    SWIFT
      host.prepareOpen(uri: uri)
      host.beginMediaIO()
      respondOffMain(queue: host.jsonQueue, keeping: host, result: { value in
        host.onNowPlayingChanged?(host)
        result(value)
        host.endMediaIO()
      }) {
        try host.open(
          uri: uri,
          httpHeaders: headers,
          httpReadAheadBytes: readAhead,
          httpBackBufferBytes: backBuffer
        )
        return nil as Any?
      }
    SWIFT
    replace!(source, "        try host.seek(positionMicros: positionMicros)\n        result(nil)", <<~'SWIFT'.lines.map { |l| "        #{l}" }.join.rstrip)
      host.beginMediaIO()
      respondOffMain(queue: host.jsonQueue, keeping: host, result: { value in
        result(value)
        host.endMediaIO()
      }) {
        try host.seek(positionMicros: positionMicros)
        return nil as Any?
      }
    SWIFT
    {
      '  func attach(view: ErikaMetalSurfaceView) throws {' => 'try? self.attach(view: view)',
      '  func attach(texture: ErikaFlutterTextureSurface) throws {' => 'try? self.attach(texture: texture)',
      '  func detach(viewId: Int64?) {' => 'self.detach(viewId: viewId)',
      '  func resizeFromAttachedView() {' => 'self.resizeFromAttachedView()',
      '  func resizeFromAttachedTexture() {' => 'self.resizeFromAttachedTexture()',
      '  private func reportDisplayHeadroom() {' => 'self.reportDisplayHeadroom()'
    }.each do |anchor, work|
      replace!(source, anchor, "#{anchor}\n    if deferDuringMediaIO({ #{work} }) { return }")
    end
    replace!(source, '        try command(host)', '        if host.deferDuringMediaIO({ _ = self.performRemoteCommand(command) }) { return .success }' + "\n        try command(host)")
    replace!(source, '      try host.seek(positionMicros: UInt64(boundedPosition * 1_000_000))', <<~'SWIFT'.lines.map { |l| "      #{l}" }.join.rstrip)
      host.beginMediaIO()
      self.respondOffMain(queue: host.jsonQueue, keeping: host, result: { _ in
        host.endMediaIO()
      }) {
        try host.seek(positionMicros: UInt64(boundedPosition * 1_000_000))
        return nil as Any?
      }
    SWIFT
    source
  end

  def self.install(installer, root)
    target = installer.pods_project.targets.find { |t| t.name == 'erika_flutter' }
    raise 'Erika media I/O patch: pod target missing' unless target
    file = target.source_build_phase.files.find { |f| File.basename(f.file_ref.path) == 'ErikaFlutterPlugin.swift' }
    raise 'Erika media I/O patch: Swift source missing' unless file
    original = File.join(root, 'Flutter/ephemeral/.symlinks/plugins/erika_flutter/macos/Classes/ErikaFlutterPlugin.swift')
    output = File.join(root, 'Flutter/ephemeral/patched_plugins/erika_flutter/ErikaFlutterPlugin.swift')
    require 'fileutils'
    FileUtils.mkdir_p(File.dirname(output))
    File.write(output, patch(File.read(original)))
    file.file_ref.path = output
    file.file_ref.source_tree = '<absolute>'
  end
end
