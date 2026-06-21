import 'package:flutter/material.dart';

class ProGate extends StatelessWidget {
  final Widget child;
  final bool replacePage;

  const ProGate({
    super.key,
    required this.child,
    this.replacePage = false,
  });

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
