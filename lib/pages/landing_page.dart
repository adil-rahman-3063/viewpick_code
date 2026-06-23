import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:url_launcher/url_launcher.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _floatController;
  late AnimationController _shimmerController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _floatAnimation;
  late Animation<double> _shimmerAnimation;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _floatController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat(reverse: true);
    _shimmerController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _floatAnimation = Tween<double>(begin: -8, end: 8).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );
    _shimmerAnimation = Tween<double>(begin: -1, end: 2).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );

    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _floatController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final size = MediaQuery.of(context).size;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          // Animated background
          _AnimatedBackground(colorScheme: colorScheme),

          // Main content
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: isLandscape
                  ? _LandscapeLayout(
                      floatAnimation: _floatAnimation,
                      shimmerAnimation: _shimmerAnimation,
                      colorScheme: colorScheme,
                      size: size,
                    )
                  : _PortraitLayout(
                      floatAnimation: _floatAnimation,
                      shimmerAnimation: _shimmerAnimation,
                      colorScheme: colorScheme,
                      size: size,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Animated Background ────────────────────────────────────────────────────

class _AnimatedBackground extends StatefulWidget {
  final ColorScheme colorScheme;
  const _AnimatedBackground({required this.colorScheme});

  @override
  State<_AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<_AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 12),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _BackgroundPainter(
            progress: _controller.value,
            primaryColor: cs.primary,
            surfaceColor: cs.surface,
            tertiaryColor: cs.tertiary,
          ),
          child: Container(),
        );
      },
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  final double progress;
  final Color primaryColor;
  final Color surfaceColor;
  final Color tertiaryColor;

  _BackgroundPainter({
    required this.progress,
    required this.primaryColor,
    required this.surfaceColor,
    required this.tertiaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Base gradient
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          surfaceColor,
          Color.lerp(surfaceColor, primaryColor, 0.08)!,
          Color.lerp(surfaceColor, tertiaryColor, 0.05)!,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Floating orbs
    _drawOrb(canvas, size, progress, 0.15, 0.2, size.width * 0.35,
        primaryColor.withOpacity(0.12));
    _drawOrb(canvas, size, progress + 0.33, 0.8, 0.7, size.width * 0.28,
        tertiaryColor.withOpacity(0.08));
    _drawOrb(canvas, size, progress + 0.66, 0.5, 0.9, size.width * 0.22,
        primaryColor.withOpacity(0.07));
  }

  void _drawOrb(Canvas canvas, Size size, double t, double cx, double cy,
      double radius, Color color) {
    final angle = t * 2 * math.pi;
    final x = size.width * cx + math.cos(angle) * size.width * 0.04;
    final y = size.height * cy + math.sin(angle) * size.height * 0.04;

    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color, color.withOpacity(0)],
      ).createShader(Rect.fromCircle(center: Offset(x, y), radius: radius));
    canvas.drawCircle(Offset(x, y), radius, paint);
  }

  @override
  bool shouldRepaint(_BackgroundPainter old) => old.progress != progress;
}

// ─── Portrait Layout ─────────────────────────────────────────────────────────

class _PortraitLayout extends StatelessWidget {
  final Animation<double> floatAnimation;
  final Animation<double> shimmerAnimation;
  final ColorScheme colorScheme;
  final Size size;

  const _PortraitLayout({
    required this.floatAnimation,
    required this.shimmerAnimation,
    required this.colorScheme,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top nav bar
        _TopBar(colorScheme: colorScheme),

        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: size.width * 0.08,
              ),
              child: Column(
                children: [
                  SizedBox(height: size.height * 0.06),

                  // Hero logo + floating icon
                  _HeroLogo(
                    floatAnimation: floatAnimation,
                    shimmerAnimation: shimmerAnimation,
                    colorScheme: colorScheme,
                    size: size,
                    isLandscape: false,
                  ),

                  SizedBox(height: size.height * 0.05),

                  // Tagline
                  _Tagline(colorScheme: colorScheme, isLandscape: false),

                  SizedBox(height: size.height * 0.06),

                  // CTA Buttons
                  _CtaButtons(colorScheme: colorScheme, isLandscape: false),

                  SizedBox(height: size.height * 0.06),

                  // Feature pills
                  _FeaturePills(colorScheme: colorScheme),

                  SizedBox(height: size.height * 0.06),

                  // Stats row
                  _StatsRow(colorScheme: colorScheme),

                  SizedBox(height: size.height * 0.06),

                  // Developer section
                  _DeveloperSection(colorScheme: colorScheme),

                  SizedBox(height: size.height * 0.04),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Landscape Layout ────────────────────────────────────────────────────────

class _LandscapeLayout extends StatelessWidget {
  final Animation<double> floatAnimation;
  final Animation<double> shimmerAnimation;
  final ColorScheme colorScheme;
  final Size size;

  const _LandscapeLayout({
    required this.floatAnimation,
    required this.shimmerAnimation,
    required this.colorScheme,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TopBar(colorScheme: colorScheme),
        Expanded(
          child: Row(
            children: [
              // Left: hero branding
              Expanded(
                flex: 5,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: size.width * 0.05,
                    right: size.width * 0.03,
                    top: 16,
                    bottom: 16,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _HeroLogo(
                        floatAnimation: floatAnimation,
                        shimmerAnimation: shimmerAnimation,
                        colorScheme: colorScheme,
                        size: size,
                        isLandscape: true,
                      ),
                      const SizedBox(height: 20),
                      _Tagline(colorScheme: colorScheme, isLandscape: true),
                      const SizedBox(height: 28),
                      _CtaButtons(colorScheme: colorScheme, isLandscape: true),
                    ],
                  ),
                ),
              ),

              // Right: features + stats
              Expanded(
                flex: 4,
                child: Padding(
                  padding: EdgeInsets.only(
                    right: size.width * 0.05,
                    left: size.width * 0.02,
                    top: 16,
                    bottom: 16,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _FeaturePills(colorScheme: colorScheme),
                        const SizedBox(height: 24),
                        _StatsRow(colorScheme: colorScheme),
                        const SizedBox(height: 24),
                        _DeveloperSection(colorScheme: colorScheme),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Shared Widgets ──────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final ColorScheme colorScheme;
  const _TopBar({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          // Mini logo
          Text(
            'VP',
            style: TextStyle(
              fontFamily: 'BitcountGridSingle',
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
          const Spacer(),
          // Ghost "Explore" button
          _GhostButton(
            label: 'Explore',
            colorScheme: colorScheme,
            onTap: () => Navigator.of(context).pushNamed('/home'),
          ),
        ],
      ),
    );
  }
}

class _GhostButton extends StatefulWidget {
  final String label;
  final ColorScheme colorScheme;
  final VoidCallback onTap;
  const _GhostButton({
    required this.label,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  State<_GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<_GhostButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: _hovered
                ? widget.colorScheme.primary.withOpacity(0.15)
                : Colors.transparent,
            border: Border.all(
              color: _hovered
                  ? widget.colorScheme.primary
                  : widget.colorScheme.outline.withOpacity(0.4),
              width: 1.2,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: _hovered
                  ? widget.colorScheme.primary
                  : widget.colorScheme.onSurface.withOpacity(0.7),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroLogo extends StatelessWidget {
  final Animation<double> floatAnimation;
  final Animation<double> shimmerAnimation;
  final ColorScheme colorScheme;
  final Size size;
  final bool isLandscape;

  const _HeroLogo({
    required this.floatAnimation,
    required this.shimmerAnimation,
    required this.colorScheme,
    required this.size,
    required this.isLandscape,
  });

  @override
  Widget build(BuildContext context) {
    final logoSize = isLandscape ? 54.0 : 62.0;
    final iconSize = isLandscape ? 52.0 : 64.0;

    return Column(
      crossAxisAlignment:
          isLandscape ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        // Floating play icon orb
        AnimatedBuilder(
          animation: floatAnimation,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, floatAnimation.value),
              child: child,
            );
          },
          child: Container(
            width: iconSize + 20,
            height: iconSize + 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  colorScheme.primary.withOpacity(0.25),
                  colorScheme.primary.withOpacity(0.05),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withOpacity(0.3),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              Icons.play_circle_rounded,
              size: iconSize,
              color: colorScheme.primary,
            ),
          ),
        ),

        const SizedBox(height: 20),

        // VIEWPICK wordmark with shimmer
        AnimatedBuilder(
          animation: shimmerAnimation,
          builder: (context, child) {
            return ShaderMask(
              shaderCallback: (bounds) {
                return LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    colorScheme.primary,
                    Color.lerp(colorScheme.primary, Colors.white, 0.7)!,
                    colorScheme.primary,
                  ],
                  stops: [
                    (shimmerAnimation.value - 0.4).clamp(0.0, 1.0),
                    shimmerAnimation.value.clamp(0.0, 1.0),
                    (shimmerAnimation.value + 0.4).clamp(0.0, 1.0),
                  ],
                ).createShader(bounds);
              },
              child: child,
            );
          },
          child: Text(
            'VIEWPICK',
            style: TextStyle(
              fontFamily: 'BitcountGridSingle',
              fontSize: logoSize,
              fontWeight: FontWeight.bold,
              letterSpacing: isLandscape ? 5 : 6,
              color: Colors.white,
              height: 1.1,
            ),
          ),
        ),

        const SizedBox(height: 6),

        // Subtitle badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withOpacity(0.5),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colorScheme.primary.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Text(
            'Your Personal Movie Companion',
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ],
    );
  }
}

class _Tagline extends StatelessWidget {
  final ColorScheme colorScheme;
  final bool isLandscape;
  const _Tagline({required this.colorScheme, required this.isLandscape});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          isLandscape ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Text(
          isLandscape
              ? 'Discover. Track.\nNever miss a frame.'
              : 'Discover. Track.\nNever miss a frame.',
          textAlign: isLandscape ? TextAlign.left : TextAlign.center,
          style: TextStyle(
            fontSize: isLandscape ? 22 : 26,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
            height: 1.3,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Swipe through thousands of movies & series,\nbuild your watchlist, and get smart picks.',
          textAlign: isLandscape ? TextAlign.left : TextAlign.center,
          style: TextStyle(
            fontSize: isLandscape ? 13 : 14,
            color: colorScheme.onSurface.withOpacity(0.55),
            height: 1.6,
          ),
        ),
      ],
    );
  }
}

class _CtaButtons extends StatelessWidget {
  final ColorScheme colorScheme;
  final bool isLandscape;
  const _CtaButtons({required this.colorScheme, required this.isLandscape});

  @override
  Widget build(BuildContext context) {
    if (isLandscape) {
      return Row(
        children: [
          _PrimaryButton(
            label: 'Sign Up',
            colorScheme: colorScheme,
            onTap: () => Navigator.of(context).pushNamed('/register'),
          ),
          const SizedBox(width: 14),
          _OutlineButton(
            label: 'Log In',
            colorScheme: colorScheme,
            onTap: () => Navigator.of(context).pushNamed('/login'),
          ),
        ],
      );
    }
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: _PrimaryButton(
            label: 'Sign Up — It\'s Free',
            colorScheme: colorScheme,
            onTap: () => Navigator.of(context).pushNamed('/register'),
            fullWidth: true,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: _OutlineButton(
            label: 'Log In',
            colorScheme: colorScheme,
            onTap: () => Navigator.of(context).pushNamed('/login'),
            fullWidth: true,
          ),
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatefulWidget {
  final String label;
  final ColorScheme colorScheme;
  final VoidCallback onTap;
  final bool fullWidth;
  const _PrimaryButton({
    required this.label,
    required this.colorScheme,
    required this.onTap,
    this.fullWidth = false,
  });

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  late AnimationController _scaleCtrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
      value: 1.0,
    );
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate(_scaleCtrl);
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => _scaleCtrl.forward(),
        onTapUp: (_) {
          _scaleCtrl.reverse();
          widget.onTap();
        },
        onTapCancel: () => _scaleCtrl.reverse(),
        child: ScaleTransition(
          scale: _scale,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(
              horizontal: widget.fullWidth ? 24 : 28,
              vertical: 15,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _hovered
                    ? [
                        widget.colorScheme.primary,
                        Color.lerp(
                            widget.colorScheme.primary,
                            widget.colorScheme.tertiary,
                            0.3)!,
                      ]
                    : [
                        widget.colorScheme.primary,
                        widget.colorScheme.primary,
                      ],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: _hovered
                  ? [
                      BoxShadow(
                        color: widget.colorScheme.primary.withOpacity(0.45),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: widget.colorScheme.primary.withOpacity(0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
            ),
            child: Center(
              child: Text(
                widget.label,
                style: TextStyle(
                  color: widget.colorScheme.onPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlineButton extends StatefulWidget {
  final String label;
  final ColorScheme colorScheme;
  final VoidCallback onTap;
  final bool fullWidth;
  const _OutlineButton({
    required this.label,
    required this.colorScheme,
    required this.onTap,
    this.fullWidth = false,
  });

  @override
  State<_OutlineButton> createState() => _OutlineButtonState();
}

class _OutlineButtonState extends State<_OutlineButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
            horizontal: widget.fullWidth ? 24 : 28,
            vertical: 15,
          ),
          decoration: BoxDecoration(
            color: _hovered
                ? widget.colorScheme.primary.withOpacity(0.1)
                : Colors.transparent,
            border: Border.all(
              color: _hovered
                  ? widget.colorScheme.primary
                  : widget.colorScheme.outline.withOpacity(0.6),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: TextStyle(
                color: _hovered
                    ? widget.colorScheme.primary
                    : widget.colorScheme.onSurface.withOpacity(0.8),
                fontWeight: FontWeight.w600,
                fontSize: 15,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Feature Pills ────────────────────────────────────────────────────────────

class _FeaturePills extends StatelessWidget {
  final ColorScheme colorScheme;
  const _FeaturePills({required this.colorScheme});

  static const _features = [
    (Icons.swipe_rounded, 'Swipe to Discover'),
    (Icons.bookmark_rounded, 'Personal Watchlist'),
    (Icons.auto_awesome_rounded, 'Smart Picks'),
    (Icons.explore_rounded, 'Browse & Explore'),
    (Icons.star_rounded, 'Rate & Review'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: _features.map((f) => _FeaturePill(
        icon: f.$1,
        label: f.$2,
        colorScheme: colorScheme,
      )).toList(),
    );
  }
}

class _FeaturePill extends StatefulWidget {
  final IconData icon;
  final String label;
  final ColorScheme colorScheme;
  const _FeaturePill({
    required this.icon,
    required this.label,
    required this.colorScheme,
  });

  @override
  State<_FeaturePill> createState() => _FeaturePillState();
}

class _FeaturePillState extends State<_FeaturePill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: _hovered
              ? widget.colorScheme.primaryContainer.withOpacity(0.6)
              : widget.colorScheme.surfaceContainerHighest.withOpacity(0.4),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: _hovered
                ? widget.colorScheme.primary.withOpacity(0.5)
                : widget.colorScheme.outline.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.icon,
              size: 16,
              color: _hovered
                  ? widget.colorScheme.primary
                  : widget.colorScheme.onSurface.withOpacity(0.6),
            ),
            const SizedBox(width: 7),
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 12.5,
                color: _hovered
                    ? widget.colorScheme.onPrimaryContainer
                    : widget.colorScheme.onSurface.withOpacity(0.65),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Stats Row ────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final ColorScheme colorScheme;
  const _StatsRow({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.15),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _StatItem(
              value: '500K+', label: 'Titles', colorScheme: colorScheme),
          _Divider(colorScheme: colorScheme),
          _StatItem(
              value: '100%', label: 'Free', colorScheme: colorScheme),
          _Divider(colorScheme: colorScheme),
          _StatItem(
              value: '∞', label: 'Swipes', colorScheme: colorScheme),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  final ColorScheme colorScheme;
  const _StatItem({
    required this.value,
    required this.label,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: colorScheme.primary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: colorScheme.onSurface.withOpacity(0.5),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  final ColorScheme colorScheme;
  const _Divider({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      width: 1,
      color: colorScheme.outline.withOpacity(0.2),
    );
  }
}

// ─── Developer Section ────────────────────────────────────────────────────────

class _DeveloperSection extends StatelessWidget {
  final ColorScheme colorScheme;
  const _DeveloperSection({required this.colorScheme});

  static const _links = [
    (
      icon: Icons.camera_alt_rounded,
      label: 'Instagram',
      handle: '@adil__rahman_',
      url: 'https://www.instagram.com/adil__rahman_/',
      color: Color(0xFFE1306C),
    ),
    (
      icon: Icons.work_rounded,
      label: 'LinkedIn',
      handle: 'adil-rahiman',
      url: 'https://www.linkedin.com/in/adil-rahiman-3815b5290/',
      color: Color(0xFF0A66C2),
    ),
    (
      icon: Icons.code_rounded,
      label: 'GitHub',
      handle: 'adil-rahman-3063',
      url: 'https://github.com/adil-rahman-3063',
      color: Color(0xFF6E40C9),
    ),
    (
      icon: Icons.email_rounded,
      label: 'Email',
      handle: 'viewpick10@gmail.com',
      url: 'mailto:viewpick10@gmail.com',
      color: Color(0xFFEA4335),
    ),
  ];

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.15),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primary,
                      colorScheme.tertiary,
                    ],
                  ),
                ),
                child: Icon(
                  Icons.person_rounded,
                  size: 20,
                  color: colorScheme.onPrimary,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Developer',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface.withOpacity(0.5),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.8,
                    ),
                  ),
                  Text(
                    'Adil Rahman',
                    style: TextStyle(
                      fontSize: 16,
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Divider
          Container(
            height: 1,
            color: colorScheme.outline.withOpacity(0.12),
          ),
          const SizedBox(height: 16),
          // Social links grid
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: _links.map((link) {
              return _SocialLink(
                icon: link.icon,
                label: link.label,
                handle: link.handle,
                accentColor: link.color,
                colorScheme: colorScheme,
                onTap: () => _launch(link.url),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _SocialLink extends StatefulWidget {
  final IconData icon;
  final String label;
  final String handle;
  final Color accentColor;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _SocialLink({
    required this.icon,
    required this.label,
    required this.handle,
    required this.accentColor,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  State<_SocialLink> createState() => _SocialLinkState();
}

class _SocialLinkState extends State<_SocialLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _hovered
                ? widget.accentColor.withOpacity(0.12)
                : widget.colorScheme.surfaceContainerHighest.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered
                  ? widget.accentColor.withOpacity(0.5)
                  : widget.colorScheme.outline.withOpacity(0.15),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _hovered
                      ? widget.accentColor.withOpacity(0.2)
                      : widget.accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  widget.icon,
                  size: 16,
                  color: widget.accentColor,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 10,
                      color: widget.colorScheme.onSurface.withOpacity(0.45),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    widget.handle,
                    style: TextStyle(
                      fontSize: 12,
                      color: _hovered
                          ? widget.accentColor
                          : widget.colorScheme.onSurface.withOpacity(0.8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
