import 'package:flutter/material.dart';
import 'friday_motion.dart';

/// Covers legacy MaterialPageRoute calls too, without changing their return
/// values, route settings or navigation stack.
class FridayPageTransitions extends PageTransitionsBuilder {
  const FridayPageTransitions();
  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext c,
      Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    if (FridayMotion.reduced(c)) return child;
    final a = animation.drive(CurveTween(curve: FridayMotion.out));
    return FadeTransition(opacity: a, child: SlideTransition(
      position: a.drive(Tween(begin: const Offset(.07, 0), end: Offset.zero)),
      child: ScaleTransition(scale: a.drive(Tween(begin: .97, end: 1.0)), child: child)));
  }
}
ThemeData withFridayMotion(ThemeData theme) => theme.copyWith(
  pageTransitionsTheme: const PageTransitionsTheme(builders: {
    TargetPlatform.android: FridayPageTransitions(),
    TargetPlatform.iOS: FridayPageTransitions(),
    TargetPlatform.linux: FridayPageTransitions(),
    TargetPlatform.macOS: FridayPageTransitions(),
    TargetPlatform.windows: FridayPageTransitions(),
    TargetPlatform.fuchsia: FridayPageTransitions(),
  }));
