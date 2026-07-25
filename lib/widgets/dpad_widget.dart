import 'package:flutter/material.dart';
import '../services/tv_remote_controller.dart';
import '../theme/app_theme.dart';

class DPadWidget extends StatelessWidget {
  final Function(RemoteCommand command) onCommand;

  const DPadWidget({
    Key? key,
    required this.onCommand,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const double dpadSize = 250.0;
    const double okButtonSize = 80.0;

    return Center(
      child: Container(
        width: dpadSize,
        height: dpadSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppTheme.dpadGradient,
          border: Border.all(color: AppTheme.cardBorder, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.6),
              blurRadius: 24,
              spreadRadius: 2,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: AppTheme.primaryCyan.withOpacity(0.08),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // UP Button
            Positioned(
              top: 10,
              child: _DPadDirectionButton(
                icon: Icons.keyboard_arrow_up_rounded,
                onPressed: () => onCommand(RemoteCommand.up),
                tooltip: 'Up',
              ),
            ),

            // DOWN Button
            Positioned(
              bottom: 10,
              child: _DPadDirectionButton(
                icon: Icons.keyboard_arrow_down_rounded,
                onPressed: () => onCommand(RemoteCommand.down),
                tooltip: 'Down',
              ),
            ),

            // LEFT Button
            Positioned(
              left: 10,
              child: _DPadDirectionButton(
                icon: Icons.keyboard_arrow_left_rounded,
                onPressed: () => onCommand(RemoteCommand.left),
                tooltip: 'Left',
              ),
            ),

            // RIGHT Button
            Positioned(
              right: 10,
              child: _DPadDirectionButton(
                icon: Icons.keyboard_arrow_right_rounded,
                onPressed: () => onCommand(RemoteCommand.right),
                tooltip: 'Right',
              ),
            ),

            // Central OK Button
            GestureDetector(
              onTap: () => onCommand(RemoteCommand.select),
              child: Container(
                width: okButtonSize,
                height: okButtonSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppTheme.okButtonGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryCyan.withOpacity(0.5),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Center(
                  child: Text(
                    'OK',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DPadDirectionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  const _DPadDirectionButton({
    Key? key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      iconSize: 42,
      tooltip: tooltip,
      splashRadius: 32,
      splashColor: AppTheme.primaryCyan.withOpacity(0.3),
      highlightColor: AppTheme.primaryBlue.withOpacity(0.2),
      icon: Icon(
        icon,
        color: AppTheme.textPrimary,
      ),
      onPressed: onPressed,
    );
  }
}
