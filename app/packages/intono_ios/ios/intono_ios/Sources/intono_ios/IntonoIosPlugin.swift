import AVFAudio
import Flutter
import IntonoNative
import UIKit

/// The platform side of the Flutter app on iOS (ADR 0010): microphone permission, the AVAudioEngine session and the engine's lifetime,
/// behind the method channel `intono/audio` with the same calls as the Kotlin side. No audio crosses the channel; Dart reads frames from
/// the engine itself over dart:ffi.
public class IntonoIosPlugin: NSObject, FlutterPlugin {
  private var session: OpaquePointer?
  private var soak = false
  private var lastError = ""

  public static func register(with registrar: FlutterPluginRegistrar) {
    _ = intono_ios_link_c_api()   // keeps the C API that Dart looks up with dlsym in the binary
    let channel = FlutterMethodChannel(name: "intono/audio", binaryMessenger: registrar.messenger())
    let instance = IntonoIosPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    // Never record in the background: Dart stops capture on its own lifecycle signal first, this is the backstop.
    NotificationCenter.default.addObserver(instance, selector: #selector(didEnterBackground),
                                           name: UIApplication.didEnterBackgroundNotification, object: nil)
  }

  @objc private func didEnterBackground() { stop() }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "start":
      withPermission { ok in result(ok && self.open(soakMinutes: 0, inline: false)) }
    case "startSoak":
      let minutes = args["minutes"] as? Int ?? 30
      let inline = args["inline"] as? Bool ?? false
      withPermission { ok in
        let started = ok && self.open(soakMinutes: minutes, inline: inline)
        if started { UIApplication.shared.isIdleTimerDisabled = true }   // the screen stays on during a soak
        result(started)
      }
    case "stop":
      stop()
      result(nil)
    case "enginePointer":
      if let s = session { result(Int(intono_ios_engine(s))) } else { result(0) }
    case "setDrone":
      guard let s = session else { result(false); return }
      let on = args["enabled"] as? Bool ?? false
      let midi = args["midiNote"] as? Int ?? 57
      let gain = args["gain"] as? Double ?? 0.3
      result(intono_ios_set_drone(s, on ? 1 : 0, Int32(midi), Float(gain)) == 1)
    // Replay (ADR 0013): the audio stays in the shim's RAM ring; Swift never sees a sample.
    case "replayArm":
      guard let s = session else { result(false); return }
      result(intono_ios_replay_arm(s, args["seconds"] as? Double ?? 60) == 1)
    case "replayFreeze":
      if let s = session { intono_ios_replay_freeze(s) }
      result(nil)
    case "replayPlay":
      guard let s = session else { result(false); return }
      result(intono_ios_replay_play(s, args["from"] as? Double ?? 0, args["to"] as? Double ?? 0) == 1)
    case "replayStop":
      if let s = session { intono_ios_replay_stop(s) }
      result(nil)
    case "replayRelease":
      if let s = session { intono_ios_replay_release(s) }
      result(nil)
    case "replayPlaying":
      if let s = session { result(intono_ios_replay_playing(s) == 1) } else { result(false) }
    case "headphones":
      result(intono_ios_headphones() == 1)
    case "info":
      if let s = session { result(text { buf, cap in intono_ios_info(s, buf, cap) }) } else { result("stopped") }
    case "lastError":
      result(lastError)
    case "soakStatus":
      if let s = session, soak { result(text { buf, cap in intono_ios_soak_status(s, buf, cap) }) } else { result("no soak running") }
    case "finishSoak":
      guard let s = session, soak else { result("no soak running"); return }
      let report = text { buf, cap in intono_ios_finish_soak(s, buf, cap) }
      stop()
      result(report)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func open(soakMinutes: Int, inline: Bool) -> Bool {
    if session != nil { return soakMinutes == 0 && !soak }
    var err = [CChar](repeating: 0, count: 512)
    session = intono_ios_start(Int32(soakMinutes), inline ? 1 : 0, &err, Int32(err.count))
    if session == nil {
      lastError = String(cString: err)
      return false
    }
    lastError = ""
    soak = soakMinutes > 0
    return true
  }

  private func stop() {
    if let s = session { intono_ios_stop(s) }
    session = nil
    soak = false
    UIApplication.shared.isIdleTimerDisabled = false
  }

  /// Calls a text function of the C API into a buffer, growing it once if the text did not fit.
  private func text(_ fn: (UnsafeMutablePointer<CChar>, Int32) -> Int32) -> String {
    var cap = 8192
    for _ in 0..<2 {
      var buf = [CChar](repeating: 0, count: cap)
      let n = Int(fn(&buf, Int32(cap)))
      if n < cap { return String(cString: buf) }
      cap = n + 1
    }
    return ""
  }

  private func withPermission(_ done: @escaping (Bool) -> Void) {
    let finish: (Bool) -> Void = { ok in
      DispatchQueue.main.async {
        if !ok { self.lastError = "no microphone permission" }
        done(ok)
      }
    }
    if #available(iOS 17.0, *) {
      switch AVAudioApplication.shared.recordPermission {
      case .granted: done(true)
      case .denied: finish(false)
      default: AVAudioApplication.requestRecordPermission(completionHandler: finish)
      }
    } else {
      let s = AVAudioSession.sharedInstance()
      switch s.recordPermission {
      case .granted: done(true)
      case .denied: finish(false)
      default: s.requestRecordPermission(finish)
      }
    }
  }
}
