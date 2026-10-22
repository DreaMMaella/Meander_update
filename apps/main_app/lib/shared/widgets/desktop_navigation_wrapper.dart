import 'package:canvas_app/core/services/deep_link_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DesktopNavigationWrapper extends StatelessWidget {
  final Widget? child;

  const DesktopNavigationWrapper({super.key, required this.child});

  void _handleBack() {
    final nav = navigatorKey.currentState;
    if (nav != null && nav.canPop()) {
      nav.maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _handleBack},
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons == kBackMouseButton) {
            _handleBack();
          }
        },
        child: child!,
      ),
    );
  }
}
