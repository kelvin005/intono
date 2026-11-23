import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intono_app/src/frame_poller.dart';
import 'package:intono_app/src/meter_state.dart';

import 'fake_engine.dart';

void main() {
  group('FramePoller', () {
    test('drains every queued frame in batches and keeps the newest', () {
      final e = FakeEngine(capacity: 64);
      for (var i = 0; i < 150; i++) {
        e.queuedFrames.add(frame(t: i * 0.005, midi: 69, cents: i.toDouble() / 10));
      }
      final p = FramePoller(e);
      final s = p.pollFrames();
      expect(e.queuedFrames, isEmpty);
      expect(e.readFramesCalls, 3); // 64 + 64 + 22: the last short batch ends the loop
      expect(s.cents, closeTo(14.9, 1e-9));
      expect(s.midiNote, 69);
      expect(s.voiced, isTrue);
    });

    test('an exact multiple of the capacity needs one more empty read', () {
      final e = FakeEngine(capacity: 64);
      for (var i = 0; i < 128; i++) {
        e.queuedFrames.add(frame(t: i * 0.005));
      }
      FramePoller(e).pollFrames();
      expect(e.readFramesCalls, 3);
      expect(e.queuedFrames, isEmpty);
    });

    test('an unvoiced newest frame turns the meter off', () {
      final e = FakeEngine();
      e.queuedFrames.addAll([frame(t: 0.0), frame(t: 0.1, voiced: false)]);
      expect(FramePoller(e).pollFrames().voiced, isFalse);
    });

    test('no new frames leaves the state exactly as it was', () {
      final e = FakeEngine();
      e.queuedFrames.add(frame(cents: 4));
      final p = FramePoller(e);
      final first = p.pollFrames();
      final second = p.pollFrames();
      expect(identical(first, second), isTrue);
      expect(MeterState.silent.voiced, isFalse);
      expect(FramePoller(FakeEngine()).pollFrames(), same(MeterState.silent));
    });

    test('notes are counted and the latest is kept', () {
      final e = FakeEngine();
      e.queuedNotes.add(note(midi: 69, mean: 2));
      e.queuedNotes.add(note(midi: 71, mean: -6));
      final p = FramePoller(e);
      p.pollNotes();
      expect(p.noteCount, 2);
      expect(p.lastNote!.midiNote, 71);
      e.queuedNotes.add(note(midi: 72, mean: 1));
      p.pollNotes();
      expect(p.noteCount, 3);
      expect(p.lastNote!.midiNote, 72);
    });
  });

  group('PollingController (on the frame ticker)', () {
    testWidgets('polls once per frame and publishes the newest state', (tester) async {
      final e = FakeEngine();
      final c = PollingController(vsync: tester, engine: e);
      c.start();
      e.queuedFrames.add(frame(cents: 1));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(c.meter.value.cents, closeTo(1, 1e-9));
      e.queuedFrames.add(frame(cents: 2));
      await tester.pump(const Duration(milliseconds: 16));
      expect(c.meter.value.cents, closeTo(2, 1e-9));
      final calls = e.readFramesCalls;
      await tester.pump(const Duration(milliseconds: 16));
      expect(e.readFramesCalls, greaterThan(calls));
      c.dispose();
    });

    testWidgets('notes are polled about every 100 ms, not every frame', (tester) async {
      final e = FakeEngine();
      final c = PollingController(vsync: tester, engine: e);
      c.start();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(e.readNotesCalls, inInclusiveRange(2, 4));
      expect(e.readFramesCalls, greaterThanOrEqualTo(19));
      c.dispose();
    });

    testWidgets('after stop() nothing is polled, and start() resumes', (tester) async {
      final e = FakeEngine();
      final c = PollingController(vsync: tester, engine: e);
      c.start();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      c.stop();
      final calls = e.readFramesCalls;
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(e.readFramesCalls, calls);
      c.start();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(e.readFramesCalls, greaterThan(calls));
      c.dispose();
    });

    testWidgets('the ticker is a vsync ticker (it follows the frame clock)', (tester) async {
      final e = FakeEngine();
      final c = PollingController(vsync: tester, engine: e);
      c.start();
      expect(c.isTicking, isTrue);
      expect(SchedulerBinding.instance.hasScheduledFrame, isTrue);
      c.stop();
      expect(c.isTicking, isFalse);
      expect(const SizedBox(), isA<Widget>());
      c.dispose();
    });
  });
}
