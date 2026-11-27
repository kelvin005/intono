import 'package:flutter/widgets.dart';

/// A plain outlined text button (the screens use only core widgets, no Material).
class AppButton extends StatelessWidget {
  const AppButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(border: Border.all(color: const Color(0xFF6B7885)), borderRadius: BorderRadius.circular(8)),
          child: Text(label),
        ),
      );
}
