import AVFoundation
import Darwin
import Flutter
import Testing
import UIKit

// ADR 0010 decision 4: smoke tests on the iOS Simulator, hosted in the app (TEST_HOST = Runner), so the C API is reached the way Dart
// reaches it: dlsym in the process (DynamicLibrary.process()). Capture itself is not asserted: the CI runner may have no audio input.

private let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)   // RTLD_DEFAULT on Darwin

private func sym<T>(_ name: String, _: T.Type) -> T? {
  guard let p = dlsym(rtldDefault, name) else { return nil }
  return unsafeBitCast(p, to: T.self)
}

private typealias IntFn = @convention(c) () -> Int32
private typealias StartFn = @convention(c) (Int32, Int32, UnsafeMutablePointer<CChar>?, Int32) -> OpaquePointer?
private typealias StopFn = @convention(c) (OpaquePointer?) -> Void
private typealias TextFn = @convention(c) (OpaquePointer?, UnsafeMutablePointer<CChar>?, Int32) -> Int32
private typealias EngineFn = @convention(c) (OpaquePointer?) -> Int
private typealias ArmFn = @convention(c) (OpaquePointer?, Double) -> Int32
private typealias SessionIntFn = @convention(c) (OpaquePointer?) -> Int32

struct RunnerTests {

  @Test func theCApiDartUsesResolvesInTheProcess() {
    for name in ["intono_create", "intono_destroy", "intono_process", "intono_read_frames", "intono_read_notes", "intono_set_tonic",
                 "intono_set_expected", "intono_drone_set", "intono_drone_render", "intono_bench_run"] {
      #expect(dlsym(rtldDefault, name) != nil, "\(name) must resolve with dlsym (DynamicLibrary.process())")
    }
    #expect(sym("intono_ios_link_c_api", IntFn.self)?() == 10)
  }

  @Test func engineCreateProcessReadDestroyWithAGeneratedTone() {
    let smoke = sym("intono_ios_smoke", IntFn.self)
    #expect(smoke != nil)
    #expect(smoke?() == 1, "a 440 Hz tone must give voiced A4 frames")
  }

  @Test func theAudioSessionStartsAndStopsOrSaysWhyNot() {
    guard let start = sym("intono_ios_start", StartFn.self), let stop = sym("intono_ios_stop", StopFn.self),
          let info = sym("intono_ios_info", TextFn.self), let engine = sym("intono_ios_engine", EngineFn.self) else {
      Issue.record("shim functions missing")
      return
    }
    var err = [CChar](repeating: 0, count: 512)
    let s = start(0, 0, &err, Int32(err.count))
    if let s {
      var buf = [CChar](repeating: 0, count: 8192)
      _ = info(s, &buf, Int32(buf.count))
      let text = String(cString: buf)
      print("ios session info:\n\(text)")   // the granted session values, for the CI log
      #expect(text.contains("AVAudioEngine"))
      #expect(text.contains("Measurement") || text.contains("measurement"))
      #expect(engine(s) != 0)
      review(s)
      stop(s)
    } else {
      let reason = String(cString: err)
      print("ios session did not start: \(reason)")
      #expect(!reason.isEmpty, "a failed start must say why")
    }
  }

  // ADR 0013 (Kelechi 2026-11-28): during review the microphone is off. Freeze stops the input engine and starts an output-only one
  // under the playback category; release stops that too. Part of the session test: Swift Testing runs tests in parallel, and two
  // audio sessions at once would collide.
  private func review(_ s: OpaquePointer) {
    guard let arm = sym("intono_ios_replay_arm", ArmFn.self), let freeze = sym("intono_ios_replay_freeze", StopFn.self),
          let release = sym("intono_ios_replay_release", StopFn.self), let input = sym("intono_ios_input_running", SessionIntFn.self),
          let output = sym("intono_ios_review_output_running", SessionIntFn.self) else {
      Issue.record("replay functions missing")
      return
    }
    #expect(input(s) == 1)
    #expect(arm(s, 60) == 1)
    freeze(s)
    #expect(input(s) == 0, "the microphone must be off during review")
    #expect(AVAudioSession.sharedInstance().category == .playback, "review uses the playback category: no input route")
    #expect(output(s) == 1, "review plays through the output-only engine")
    release(s)
    #expect(output(s) == 0)
  }

  @Test func headphonesIsAYesOrNo() {
    let v = sym("intono_ios_headphones", IntFn.self)?()
    #expect(v == 0 || v == 1)
  }
}
