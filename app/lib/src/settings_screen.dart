import 'package:flutter/widgets.dart';

import 'speech.dart';
import 'ui_button.dart';

/// Settings. v1 has one: "Clear history" (ADR 0015 decision 9), which deletes every stored session only after a confirmation; the
/// settings themselves are kept.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.onClearHistory,
    required this.onClose,
    this.spokenMode = SpokenMode.auto,
    this.onSpokenModeChanged,
  });

  final Future<void> Function() onClearHistory;
  final VoidCallback onClose;

  /// The spoken summary after a run (ADR 0017); tapping cycles auto (with headphones), on, off.
  final SpokenMode spokenMode;
  final ValueChanged<SpokenMode>? onSpokenModeChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _confirming = false;
  bool _busy = false;
  String _status = '';

  Future<void> _clear() async {
    if (_busy) return;
    setState(() => _busy = true);
    String status;
    try {
      await widget.onClearHistory();
      status = 'Practice history cleared.';
    } catch (_) {
      status = 'The history could not be cleared. Please try again.';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _confirming = false;
      _status = status;
    });
  }

  @override
  Widget build(BuildContext context) => DefaultTextStyle(
        style: const TextStyle(color: Color(0xFFE8ECEF), fontSize: 16, decoration: TextDecoration.none),
        child: ColoredBox(
          color: const Color(0xFF101418),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                AppButton(label: 'Back', onTap: widget.onClose),
                const SizedBox(height: 12),
                const Text('Settings', style: TextStyle(fontSize: 22)),
                const SizedBox(height: 20),
                if (widget.onSpokenModeChanged != null) ...[
                  AppButton(
                      label: 'Spoken summary: ${widget.spokenMode.label}',
                      onTap: () => widget.onSpokenModeChanged!(widget.spokenMode.next)),
                  const SizedBox(height: 12),
                ],
                if (!_confirming) AppButton(label: 'Clear history', onTap: () => setState(() {
                      _confirming = true;
                      _status = '';
                    })),
                if (_confirming) ...[
                  const Text('Delete every practice session stored on this phone? This cannot be undone.'),
                  const SizedBox(height: 12),
                  AppButton(label: 'Delete all history', onTap: _clear),
                  const SizedBox(height: 12),
                  AppButton(label: 'Cancel', onTap: () => setState(() => _confirming = false)),
                ],
                if (_status.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_status)),
              ]),
            ),
          ),
        ),
      );
}
