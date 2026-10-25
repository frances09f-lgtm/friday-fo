import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// UI-only tokens measured from the approved prototype.
abstract final class FridayMotion {
  static const spring = Cubic(.34, 1.56, .64, 1);
  static const out = Cubic(.22, 1, .36, 1);
  static const screen = Duration(milliseconds: 480);
  static const route = Duration(milliseconds: 450);
  static const press = Duration(milliseconds: 300);
  static const toggle = Duration(milliseconds: 400);
  static const dock = Duration(milliseconds: 500);
  static bool reduced(BuildContext c) => MediaQuery.disableAnimationsOf(c);
  static Duration duration(BuildContext c, Duration d) => reduced(c) ? Duration.zero : d;
}

/// Adds visual feedback without taking ownership of the child's gestures,
/// keyboard activation, focus, semantics or callbacks.
class MotionPress extends StatefulWidget {
  const MotionPress({super.key, required this.child, this.enabled = true, this.scale = .94});
  final Widget child;
  final bool enabled;
  final double scale;
  @override
  State<MotionPress> createState() => _MotionPressState();
}
class _MotionPressState extends State<MotionPress> {
  int? pointer;
  Offset? start;
  bool down = false;
  void release() { if (down && mounted) setState(() => down = false); pointer = null; start = null; }
  @override
  void didUpdateWidget(MotionPress old) { super.didUpdateWidget(old); if (!widget.enabled) { down = false; pointer = null; start = null; } }
  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (e) { if (widget.enabled && pointer == null) { pointer = e.pointer; start = e.position; setState(() => down = true); } },
    onPointerMove: (e) { if (e.pointer == pointer && start != null && (e.position - start!).distance > 12) release(); },
    onPointerUp: (e) { if (e.pointer == pointer) release(); },
    onPointerCancel: (e) { if (e.pointer == pointer) release(); },
    child: AnimatedScale(scale: down && !FridayMotion.reduced(context) ? widget.scale : 1,
      duration: FridayMotion.duration(context, FridayMotion.press),
      curve: down ? Curves.easeOut : FridayMotion.spring, child: widget.child));
}

class MotionEpoch extends InheritedWidget {
  const MotionEpoch({super.key, required this.epoch, required super.child});
  final int epoch;
  static int of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<MotionEpoch>()?.epoch ?? 0;
  @override
  bool updateShouldNotify(MotionEpoch old) => epoch != old.epoch;
}

/// Timers are bounded, cancelled on dispose, and never restarted by text updates.
class MotionEntrance extends StatefulWidget {
  const MotionEntrance({super.key, required this.child, this.index = 0, this.scale = .96});
  final Widget child;
  final int index;
  final double scale;
  @override
  State<MotionEntrance> createState() => _MotionEntranceState();
}
class _MotionEntranceState extends State<MotionEntrance> with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(vsync: this, duration: FridayMotion.screen);
  Timer? timer;
  int? epoch;
  bool reduce = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = MotionEpoch.of(context);
    final r = FridayMotion.reduced(context);
    if (epoch != next || reduce != r) {
      epoch = next; reduce = r; timer?.cancel(); controller.stop();
      if (r) { controller.value = 1; } else {
        controller.value = 0;
        final delay = math.min(math.max(widget.index, 0), 7) * 35;
        if (delay == 0) { controller.forward(); } else {
          timer = Timer(Duration(milliseconds: delay), () { if (mounted) controller.forward(); });
        }
      }
    }
  }
  @override
  void dispose() { timer?.cancel(); controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: controller, child: widget.child,
    builder: (c, child) {
      final t = FridayMotion.spring.transform(controller.value);
      return Opacity(opacity: controller.value.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, 18 * (1 - t)),
          child: Transform.scale(scale: widget.scale + (1 - widget.scale) * t, child: child)));
    });
}

class MotionList extends StatelessWidget {
  const MotionList({super.key, required this.children, this.padding, this.controller, this.shrinkWrap = false, this.physics});
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  final ScrollController? controller;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  @override
  Widget build(BuildContext context) => ListView(padding: padding, controller: controller,
    shrinkWrap: shrinkWrap, physics: physics, children: [
      for (var i = 0; i < children.length; i++)
        MotionEntrance(key: children[i].key ?? ValueKey(i), index: i, child: children[i]),
    ]);
}

/// Native Switch owns drag/tap/keyboard/focus/semantics; the spring track is
/// decorative and cannot intercept input. This keeps real toggles working.
class MotionSwitch extends StatefulWidget {
  const MotionSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  State<MotionSwitch> createState() => _MotionSwitchState();
}
class _MotionSwitchState extends State<MotionSwitch> {
  bool focused = false;
  @override
  Widget build(BuildContext c) {
    final s = Theme.of(c).colorScheme;
    return Stack(alignment: Alignment.center, children: [
      Switch(value: widget.value, onChanged: widget.onChanged,
        onFocusChange: (v) => setState(() => focused = v),
        thumbColor: const WidgetStatePropertyAll(Colors.transparent),
        trackColor: const WidgetStatePropertyAll(Colors.transparent),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent)),
      IgnorePointer(child: ExcludeSemantics(child: Opacity(opacity: widget.onChanged == null ? .45 : 1,
        child: TweenAnimationBuilder<double>(tween: Tween(end: widget.value ? 1 : 0),
          duration: FridayMotion.duration(c, FridayMotion.toggle), curve: FridayMotion.spring,
          builder: (c, t, _) {
            final colorT = t.clamp(0.0, 1.0);
            final x = Directionality.of(c) == TextDirection.rtl ? 1 - t : t;
            return Container(width: 52, height: 32,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(20),
                color: Color.lerp(s.surfaceContainerHigh, s.primary, colorT),
                border: Border.all(color: focused ? s.onSurface : Color.lerp(s.onSurfaceVariant, s.primary, colorT)!, width: focused ? 3 : 2)),
              child: Align(alignment: Alignment(-.65 + 1.30 * x, 0),
                child: Transform.scale(scale: 1 + .35 * t,
                  child: Container(key: const ValueKey('motion-switch-thumb'), width: 16, height: 16,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Color.lerp(s.onSurfaceVariant, s.onPrimary, colorT))))));
          }))))
    ]);
  }
}

class MotionSwitchTile extends StatelessWidget {
  const MotionSwitchTile({super.key, required this.title, this.subtitle, required this.value, required this.onChanged, this.contentPadding});
  final Widget title;
  final Widget? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final EdgeInsetsGeometry? contentPadding;
  @override
  Widget build(BuildContext c) => MergeSemantics(child: ListTile(
    contentPadding: contentPadding, title: title, subtitle: subtitle,
    onTap: onChanged == null ? null : () => onChanged!(!value),
    trailing: MotionSwitch(value: value, onChanged: onChanged)));
}

class MotionExpansion extends StatelessWidget {
  const MotionExpansion({super.key, required this.title, this.subtitle, this.leading, required this.children, this.tilePadding, this.childrenPadding});
  final Widget title;
  final Widget? subtitle, leading;
  final List<Widget> children;
  final EdgeInsetsGeometry? tilePadding, childrenPadding;
  @override
  Widget build(BuildContext c) => ExpansionTile(title: title, subtitle: subtitle, leading: leading,
    tilePadding: tilePadding, childrenPadding: childrenPadding,
    expansionAnimationStyle: AnimationStyle(duration: FridayMotion.duration(c, FridayMotion.toggle),
      reverseDuration: FridayMotion.duration(c, FridayMotion.toggle), curve: FridayMotion.out, reverseCurve: FridayMotion.out),
    children: children);
}

class MotionCard extends StatelessWidget {
  const MotionCard({super.key, required this.child, this.color, this.padding = const EdgeInsets.all(18)});
  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext c) => Material(color: color ?? Theme.of(c).colorScheme.surfaceContainer,
    borderRadius: BorderRadius.circular(28), child: Padding(padding: padding, child: child));
}

class MotionRoute<T> extends MaterialPageRoute<T> {
  MotionRoute({required super.builder, super.settings, super.fullscreenDialog});
  @override
  Duration get transitionDuration => FridayMotion.route;
  @override
  Duration get reverseTransitionDuration => FridayMotion.route;
  @override
  Widget buildTransitions(BuildContext c, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    if (FridayMotion.reduced(c)) return child;
    final curved = animation.drive(CurveTween(curve: FridayMotion.out));
    return FadeTransition(opacity: curved,
      child: SlideTransition(position: curved.drive(Tween(begin: const Offset(.07, 0), end: Offset.zero)),
        child: ScaleTransition(scale: curved.drive(Tween(begin: .97, end: 1.0)), child: child)));
  }
}

/// Keeps each page mounted at the same IndexedStack position.
class MotionTab extends StatefulWidget {
  const MotionTab({super.key, required this.active, required this.child});
  final bool active;
  final Widget child;
  @override
  State<MotionTab> createState() => _MotionTabState();
}
class _MotionTabState extends State<MotionTab> {
  int epoch = 0;
  @override
  void didUpdateWidget(MotionTab old) { super.didUpdateWidget(old); if (widget.active && !old.active) epoch++; }
  @override
  Widget build(BuildContext c) => TickerMode(enabled: widget.active,
    child: MotionEpoch(epoch: epoch, child: MotionEntrance(child: widget.child)));
}
