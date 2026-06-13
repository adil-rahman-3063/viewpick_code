import 'dart:ui';

import 'package:flutter/material.dart';
import '../pages/swipe_page.dart';
import '../pages/home_page.dart';
import '../pages/explore.dart';
import '../pages/list_page.dart';
import '../pages/profile.dart';

/// Frosted, pill-shaped bottom navigation bar with five icons.
///
/// - Shows a blurred background (BackdropFilter) with a semi-transparent
///   surface color so content behind is visible in a frosted way.
/// - Pill shape with large corner radius to form semicircles on both ends.
/// - Icons: swap (two-way), home, explore, list, profile.
/// - Icons use the theme's secondary color. The selected icon shows a
///   small accent circle behind it.
class FrostedNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  const FrostedNavBar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  static const double _height = 72.0;
  static const double _horizontalPadding = 16.0;
  static const double _pillRadius = 40.0;

  /// Handle navigation based on the nav bar item index
  static void handleNavigation(BuildContext context, int index) {
    switch (index) {
      case 0: // Swipe icon - navigate to SwipePage
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const SwipePage(),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        );
        break;
      case 1: // Home icon - navigate to HomePage
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const HomePage(),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        );
        break;
      case 2: // Explore icon - navigate to ExplorePage
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const ExplorePage(),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        );
        break;
      case 3: // List icon - navigate to ListPage
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const ListPage(),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        );
        break;
      case 4: // Profile icon - navigate to ProfilePage
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const ProfilePage(),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final secondary = colorScheme.secondary;
    final surface = colorScheme.surface;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _horizontalPadding,
        vertical: 12,
      ),
      child: SizedBox(
        height: _height,
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_pillRadius),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                height: _height,
                decoration: BoxDecoration(
                  color: surface.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(_pillRadius),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.1),
                    width: 1,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(_icons.length, (i) {
                    final item = _icons[i];
                    final selected = i == selectedIndex;
                    return _NavItem(
                      icon: item.icon,
                      index: i,
                      selected: selected,
                      color: secondary,
                      context: context,
                      onTap: onItemSelected,
                      semanticsLabel: _labels[i],
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final int index;
  final bool selected;
  final Color color;
  final BuildContext context;
  final ValueChanged<int> onTap;
  final String semanticsLabel;

  const _NavItem({
    required this.icon,
    required this.index,
    required this.selected,
    required this.color,
    required this.context,
    required this.onTap,
    required this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: semanticsLabel,
        child: InkWell(
          onTap: () {
            FrostedNavBar.handleNavigation(this.context, index);
            onTap(index); // Still call the callback for state updates
          },
          borderRadius: BorderRadius.circular(32),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  height: selected ? 44 : 40,
                  width: selected ? 44 : 40,
                  decoration: BoxDecoration(
                    color: selected
                        ? color.withValues(alpha: 0.25)
                        : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: selected
                        ? color
                        : Theme.of(context).colorScheme.onSurface,
                    size: selected ? 26 : 24,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavEntry {
  final IconData icon;
  const _NavEntry(this.icon);
}

const List<_NavEntry> _icons = [
  _NavEntry(Icons.swipe),
  _NavEntry(Icons.home_outlined),
  _NavEntry(Icons.explore_outlined),
  _NavEntry(Icons.view_list_outlined),
  _NavEntry(Icons.person_outline),
];

const List<String> _labels = ['Swipe', 'Home', 'Explore', 'List', 'Profile'];
