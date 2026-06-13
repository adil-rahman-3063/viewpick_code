import 'package:flutter/material.dart';
import 'side_nav_bar.dart';
import 'nav_bar.dart';

class ResponsiveLayout extends StatelessWidget {
  final Widget child;
  final int selectedIndex;
  final ValueChanged<int>? onItemSelected;

  const ResponsiveLayout({
    super.key,
    required this.child,
    required this.selectedIndex,
    this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    // We use MediaQuery here because we want to respond to the overall screen width
    final screenWidth = MediaQuery.of(context).size.width;

    if (screenWidth < 600) {
      // Mobile Layout (Bottom Nav)
      return Scaffold(
        extendBody: true,
        body: child,
        bottomNavigationBar: FrostedNavBar(
          selectedIndex: selectedIndex,
          onItemSelected: onItemSelected ?? (index) {},
        ),
      );
    } else {
      // Desktop/Tablet Layout (Sidebar)
      return Scaffold(
        extendBody: true,
        body: Row(
          children: [
            FrostedSideBar(
              selectedIndex: selectedIndex,
              onItemSelected: onItemSelected ?? (index) {},
            ),
            Expanded(child: child),
          ],
        ),
      );
    }
  }
}
