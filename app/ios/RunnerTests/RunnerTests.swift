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
      stop(s)
    } else {
      let reason = String(cString: err)
      print("ios session did not start: \(reason)")
      #expect(!reason.isEmpty, "a failed start must say why")
    }
  }

  @Test func headphonesIsAYesOrNo() {
    let v = sym("intono_ios_headphones", IntFn.self)?()
    #expect(v == 0 || v == 1)
  }
}
