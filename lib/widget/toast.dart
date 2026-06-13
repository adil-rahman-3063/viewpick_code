import 'dart:ui';
import 'package:flutter/material.dart';

enum ToastPosition { top, bottomLeft, bottom }

class Toast {
  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
    ToastPosition position = ToastPosition.bottom,
    VoidCallback? onUndo,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;
    
    overlayEntry = OverlayEntry(
      builder: (context) => _ToastWidget(
        message: message,
        isError: isError,
        position: position,
        onUndo: onUndo != null ? () {
          onUndo();
          overlayEntry.remove();
        } : null,
      ),
    );

    overlay.insert(overlayEntry);

    // Remove the toast after a delay
    // Longer duration if there is an undo action
    final duration = onUndo != null ? const Duration(seconds: 5) : const Duration(seconds: 2);
    
    Future.delayed(duration, () {
      if (overlayEntry.mounted) {
        overlayEntry.remove();
      }
    });
  }
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final bool isError;
  final ToastPosition position;
  final VoidCallback? onUndo;

  const _ToastWidget({
    required this.message,
    this.isError = false,
    this.position = ToastPosition.bottom,
    this.onUndo,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _opacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _offset = Tween<Offset>(
      begin: widget.position == ToastPosition.top
          ? const Offset(0, -0.5)
          : const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();

    // Start reverse animation before removing
    final displayDuration = widget.onUndo != null ? 4700 : 1700;
    Future.delayed(Duration(milliseconds: displayDuration), () {
      if (mounted) {
        _controller.reverse();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: widget.position == ToastPosition.top
          ? MediaQuery.of(context).padding.top + 10
          : null,
      bottom: widget.position == ToastPosition.bottom 
          ? 100 
          : (widget.position == ToastPosition.bottomLeft ? 20 : null),
      left: widget.position == ToastPosition.bottomLeft ? 20 : 16,
      right: widget.position == ToastPosition.bottomLeft ? null : 16,
      child: Material(
        color: Colors.transparent,
        child: Center(
          child: SlideTransition(
            position: _offset,
            child: FadeTransition(
              opacity: _opacity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: widget.isError
                          ? Theme.of(
                              context,
                            ).colorScheme.errorContainer.withValues(alpha: 0.8)
                          : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: widget.isError
                            ? Theme.of(
                                context,
                              ).colorScheme.error.withValues(alpha: 0.5)
                            : Theme.of(
                                context,
                              ).colorScheme.outline.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.isError
                              ? Icons.error_outline
                              : Icons.check_circle_outline,
                          color: widget.isError
                              ? Theme.of(context).colorScheme.onErrorContainer
                              : Theme.of(context).colorScheme.onSurface,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            widget.message,
                            style: TextStyle(
                              color: widget.isError
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.onErrorContainer
                                  : Theme.of(context).colorScheme.onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        if (widget.onUndo != null) ...[
                          const SizedBox(width: 12),
                          Container(
                            height: 24,
                            width: 1,
                            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: widget.onUndo,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              foregroundColor: Theme.of(context).colorScheme.primary,
                            ),
                            child: const Text(
                              'UNDO',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
