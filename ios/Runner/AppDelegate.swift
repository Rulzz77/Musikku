import AVFoundation
import Flutter
import MediaPlayer
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MusikKuIOSBridge") else {
      assertionFailure("Unable to create the MusikKu iOS plugin registrar.")
      return
    }
    MusikKuIOSBridge.register(with: registrar)
  }
}

private final class MusikKuIOSBridge: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static let playbackChannelName = "musikku/youtube_player"
  private static let localMediaChannelName = "musikku/local_media"
  private static let dataUsageChannelName = "musikku/data_usage"
  private static let eventChannelName = "musikku/youtube_player/events"

  private let playbackChannel: FlutterMethodChannel
  private var eventSink: FlutterEventSink?
  private var player: AVPlayer?
  private var timeObserver: Any?
  private var endObserver: NSObjectProtocol?
  private var activeVideoId = ""
  private var activeTitle = "MusikKu"
  private var activeArtist = ""
  private var activeDuration: Double = 0
  private var lastPosition: Double = 0
  private var notificationTargetsInstalled = false

  private init(messenger: FlutterBinaryMessenger) {
    playbackChannel = FlutterMethodChannel(name: Self.playbackChannelName, binaryMessenger: messenger)
    super.init()
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = MusikKuIOSBridge(messenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: instance.playbackChannel)

    let local = FlutterMethodChannel(name: localMediaChannelName, binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: local)

    let data = FlutterMethodChannel(name: dataUsageChannelName, binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: data)

    let events = FlutterEventChannel(name: eventChannelName, binaryMessenger: registrar.messenger())
    events.setStreamHandler(instance)
    instance.installRemoteCommandHandlers()
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    emitState()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    // MARK: Apple Music local library
    case "hasLocalMusicPermission":
      result(MPMediaLibrary.authorizationStatus() == .authorized)
    case "requestLocalMusicPermission":
      requestMediaPermission(result: result)
    case "shouldOpenLocalMusicSettings":
      let status = MPMediaLibrary.authorizationStatus()
      result(status == .denied || status == .restricted)
    case "openLocalMusicSettings":
      if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
      }
      result(nil)
    case "scanLocalMusic":
      guard MPMediaLibrary.authorizationStatus() == .authorized else {
        result(FlutterError(code: "MEDIA_PERMISSION_DENIED", message: "Akses Pustaka Musik belum diizinkan.", details: nil))
        return
      }
      result(scanLocalMusic())
    case "getLocalArtwork":
      let args = call.arguments as? [String: Any] ?? [:]
      let mediaId = args["mediaId"] as? String ?? ""
      result(localArtwork(mediaId: mediaId))

    // MARK: AVPlayer local audio
    case "loadLocal":
      let args = call.arguments as? [String: Any] ?? [:]
      loadLocal(args: args, result: result)
    case "play":
      player?.play()
      updateNowPlaying(playing: true)
      emitState()
      result(nil)
    case "pause", "pauseActiveAudio":
      player?.pause()
      updateNowPlaying(playing: false)
      emitState()
      result(nil)
    case "seek":
      let args = call.arguments as? [String: Any] ?? [:]
      let seconds = max(0, args["seconds"] as? Double ?? 0)
      seek(to: seconds) { result(nil) }
    case "currentTime":
      result(currentSeconds())
    case "setVolume":
      let args = call.arguments as? [String: Any] ?? [:]
      let percent = max(0, min(100, args["percent"] as? Int ?? 100))
      player?.volume = Float(percent) / 100.0
      result(nil)
    case "getNativePlaybackSnapshot":
      result(["videoId": activeVideoId, "position": currentSeconds(), "duration": activeDuration, "playing": (player?.rate ?? 0) > 0])
    case "getPlayerDebugSnapshot":
      result(["platform": "ios", "player": "AVPlayer", "videoId": activeVideoId, "state": currentState()])
    case "getHealthEvents":
      result([Any]())
    case "clearHealthEvents":
      result(nil)
    case "getNetworkType":
      result("unknown")
    case "getStats":
      result(["supported": false, "todayRxBytes": 0, "todayTxBytes": 0, "totalRxBytes": 0, "totalTxBytes": 0, "date": ""])
    case "getAudioOutputDevices":
      result(["supported": false, "devices": []])

    // MARK: Lock Screen / Control Center
    case "startNotification", "updateNotification":
      let args = call.arguments as? [String: Any] ?? [:]
      let requestedVideoId = args["videoId"] as? String ?? ""
      if !requestedVideoId.hasPrefix("local:") {
        // Lock Screen audio metadata is published only for a real local AVPlayer
        // item. iOS YouTube playback stays inside the official inline player.
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        result(nil)
        return
      }
      activeVideoId = requestedVideoId
      activeTitle = args["title"] as? String ?? activeTitle
      activeArtist = args["artist"] as? String ?? activeArtist
      if let duration = args["durationSeconds"] as? Double, duration > 0 { activeDuration = duration }
      updateNowPlaying(playing: args["playing"] as? Bool ?? ((player?.rate ?? 0) > 0))
      result(nil)
    case "stopNotification":
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
      result(nil)

    // MARK: Features that are Android-only or controlled by the official iFrame player on iOS
    case "setPlayerUiVisible", "setDataSaverLevel", "setPlaybackQuality", "setCaptionSettings",
         "setVideoCrop", "setLandscapeSystemUi":
      result(nil)
    case "exportBackup", "importBackup":
      result(FlutterError(code: "UNSUPPORTED_ON_IOS", message: "Fitur backup file belum tersedia di iOS.", details: nil))
    case "setEqualizerPreset", "setEqualizerBands":
      result(false)
    case "loadVideo", "loadYoutubeAudio":
      result(FlutterError(code: "UNSUPPORTED_ON_IOS", message: "Video YouTube di iOS dijalankan melalui YouTube iFrame Player.", details: nil))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func requestMediaPermission(result: @escaping FlutterResult) {
    let status = MPMediaLibrary.authorizationStatus()
    if status == .authorized {
      result(true)
      return
    }
    if status == .denied || status == .restricted {
      result(false)
      return
    }
    MPMediaLibrary.requestAuthorization { newStatus in
      DispatchQueue.main.async { result(newStatus == .authorized) }
    }
  }

  private func scanLocalMusic() -> [[String: Any]] {
    let songs = MPMediaQuery.songs().items ?? []
    return songs.compactMap { item in
      guard let assetURL = item.assetURL else { return nil }
      return [
        "mediaId": String(item.persistentID),
        "uri": assetURL.absoluteString,
        "title": item.title ?? "Tanpa judul",
        "artist": item.artist ?? "Artis tidak diketahui",
        "album": item.albumTitle ?? "",
        "durationMs": Int(item.playbackDuration * 1000),
        "genre": item.genre ?? ""
      ]
    }
  }

  private func localArtwork(mediaId: String) -> FlutterStandardTypedData? {
    guard let id = UInt64(mediaId) else { return nil }
    let predicate = MPMediaPropertyPredicate(value: NSNumber(value: id), forProperty: MPMediaItemPropertyPersistentID)
    let query = MPMediaQuery.songs()
    query.addFilterPredicate(predicate)
    guard let artwork = query.items?.first?.artwork,
          let image = artwork.image(at: CGSize(width: 512, height: 512)),
          let data = image.jpegData(compressionQuality: 0.88) else { return nil }
    return FlutterStandardTypedData(bytes: data)
  }

  private func loadLocal(args: [String: Any], result: @escaping FlutterResult) {
    guard let rawUri = args["mediaUri"] as? String,
          let url = URL(string: rawUri) else {
      result(FlutterError(code: "INVALID_MEDIA_URI", message: "Alamat file musik tidak valid.", details: nil))
      return
    }

    removePlayerObservers()
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.allowBluetooth, .allowAirPlay])
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      result(FlutterError(code: "AUDIO_SESSION_ERROR", message: error.localizedDescription, details: nil))
      return
    }

    let item = AVPlayerItem(url: url)
    let newPlayer = AVPlayer(playerItem: item)
    player = newPlayer
    activeVideoId = "local:\(args["mediaId"] as? String ?? "")"
    activeTitle = args["title"] as? String ?? "MusikKu"
    activeArtist = args["artist"] as? String ?? ""
    activeDuration = max(0, args["durationSeconds"] as? Double ?? 0)
    lastPosition = 0

    timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
      guard let self = self else { return }
      self.lastPosition = max(0, time.seconds.isFinite ? time.seconds : 0)
      let loaded = item.loadedTimeRanges.first?.timeRangeValue
      let bufferedEnd = loaded.map { CMTimeGetSeconds($0.start) + CMTimeGetSeconds($0.duration) } ?? self.lastPosition
      let ahead = max(0, bufferedEnd - self.lastPosition)
      let fraction = loaded != nil && self.activeDuration > 0 ? min(1, bufferedEnd / self.activeDuration) : 0
      self.emitState(bufferedAhead: ahead, bufferedFraction: fraction)
      self.updateNowPlaying(playing: newPlayer.rate > 0)
    }

    endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
      self?.emitState(forceState: "ended")
      self?.updateNowPlaying(playing: false)
    }

    let start = max(0, args["startSeconds"] as? Double ?? 0)
    if start > 0 {
      newPlayer.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
        newPlayer.play()
        self?.updateNowPlaying(playing: true)
      }
    } else {
      newPlayer.play()
    }
    updateNowPlaying(playing: true)
    emitState(forceState: "buffering")
    result(nil)
  }

  private func currentSeconds() -> Double {
    guard let player = player else { return lastPosition }
    let seconds = player.currentTime().seconds
    return seconds.isFinite ? max(0, seconds) : lastPosition
  }

  private func currentState() -> String {
    guard let player = player else { return "unstarted" }
    if player.currentItem?.status == .failed { return "error" }
    switch player.timeControlStatus {
    case .playing: return "playing"
    case .waitingToPlayAtSpecifiedRate: return "buffering"
    case .paused: return "paused"
    @unknown default: return "unknown"
    }
  }

  private func emitState(forceState: String? = nil, bufferedAhead: Double = 0, bufferedFraction: Double = 0) {
    guard let sink = eventSink else { return }
    let duration = player?.currentItem?.duration.seconds ?? activeDuration
    let durationSafe = duration.isFinite ? max(0, duration) : activeDuration
    let state = forceState ?? currentState()
    sink([
      "state": state,
      "position": currentSeconds(),
      "duration": durationSafe,
      "videoId": activeVideoId,
      "bufferedFraction": min(1, max(0, bufferedFraction)),
      "bufferedAheadSeconds": bufferedAhead,
      "networkRxBytes": 0,
      "networkType": "unknown"
    ])
  }

  private func seek(to seconds: Double, completion: @escaping () -> Void) {
    guard let player = player else { completion(); return }
    player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
      self?.lastPosition = seconds
      self?.emitState()
      completion()
    }
  }

  private func updateNowPlaying(playing: Bool) {
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: activeTitle,
      MPMediaItemPropertyArtist: activeArtist,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: currentSeconds(),
      MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0
    ]
    if activeDuration > 0 { info[MPMediaItemPropertyPlaybackDuration] = activeDuration }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  private func installRemoteCommandHandlers() {
    guard !notificationTargetsInstalled else { return }
    notificationTargetsInstalled = true
    let center = MPRemoteCommandCenter.shared()
    center.playCommand.addTarget(self, action: #selector(remotePlay(_:)))
    center.pauseCommand.addTarget(self, action: #selector(remotePause(_:)))
    center.togglePlayPauseCommand.addTarget(self, action: #selector(remoteToggle(_:)))
    center.nextTrackCommand.addTarget(self, action: #selector(remoteNext(_:)))
    center.previousTrackCommand.addTarget(self, action: #selector(remotePrevious(_:)))
    center.changePlaybackPositionCommand.addTarget(self, action: #selector(remoteSeek(_:)))
  }

  @objc private func remotePlay(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    player?.play(); updateNowPlaying(playing: true); emitState(); return .success
  }
  @objc private func remotePause(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    player?.pause(); updateNowPlaying(playing: false); emitState(); return .success
  }
  @objc private func remoteToggle(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    if (player?.rate ?? 0) > 0 { player?.pause() } else { player?.play() }
    let playing = (player?.rate ?? 0) > 0
    updateNowPlaying(playing: playing); emitState(); return .success
  }
  @objc private func remoteNext(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    playbackChannel.invokeMethod("notificationNext", arguments: nil); return .success
  }
  @objc private func remotePrevious(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    playbackChannel.invokeMethod("notificationPrevious", arguments: nil); return .success
  }
  @objc private func remoteSeek(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    guard let seekEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
    seek(to: seekEvent.positionTime) {}; return .success
  }

  private func removePlayerObservers() {
    if let observer = timeObserver, let player = player {
      player.removeTimeObserver(observer)
    }
    timeObserver = nil
    if let observer = endObserver { NotificationCenter.default.removeObserver(observer) }
    endObserver = nil
  }

  deinit { removePlayerObservers() }
}
