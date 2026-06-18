import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import 'login_prompt.dart';


class FrostedSideBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  const FrostedSideBar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  static const double _width = 80.0;
  static const double _verticalPadding = 16.0;
  static const double _pillRadius = 40.0;

  static void handleNavigation(BuildContext context, int index) {
    if (SupabaseService.currentUser() == null) {
      if (index == 0) {
        showLoginPrompt(context, message: 'Sign in to Swipe and find the perfect movie or series to watch with friends!');
        return;
      } else if (index == 3) {
        showLoginPrompt(context, message: 'Sign in to view and manage your watchlist and watched history!');
        return;
      } else if (index == 4) {
        showLoginPrompt(context, message: 'Sign in to view your profile, stats, and settings!');
        return;
      }
    }

    final routes = ['/swipe', '/home', '/explore', '/list', '/profile'];
    if (index >= 0 && index < routes.length) {
      Navigator.of(context).pushReplacementNamed(routes[index]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final secondary = colorScheme.secondary;
    final surface = colorScheme.surface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: _verticalPadding, horizontal: 12),
      child: SizedBox(
        width: _width,
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_pillRadius),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                width: _width,
                decoration: BoxDecoration(
                  color: surface.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(_pillRadius),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                    width: 1,
                  ),
                ),
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
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
            FrostedSideBar.handleNavigation(this.context, index);
            onTap(index);
          },
          borderRadius: BorderRadius.circular(32),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  height: selected ? 44 : 40,
                  width: selected ? 44 : 40,
                  decoration: BoxDecoration(
                    color: selected ? color.withValues(alpha: 0.25) : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: selected ? color : Theme.of(context).colorScheme.onSurface,
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
