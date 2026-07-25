import 'package:flutter/material.dart';
import '../services/tv_remote_controller.dart';
import '../theme/app_theme.dart';

class ActionButtonsWidget extends StatelessWidget {
  final Function(RemoteCommand command) onCommand;

  const ActionButtonsWidget({
    Key? key,
    required this.onCommand,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: AppTheme.glassBoxDecoration(borderRadius: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Power Button
          _ActionButtonItem(
            icon: Icons.power_settings_new_rounded,
            label: 'POWER',
            accentColor: AppTheme.accentPowerRed,
            onPressed: () => onCommand(RemoteCommand.power),
          ),

          // Back Button
          _ActionButtonItem(
            icon: Icons.arrow_back_rounded,
            label: 'BACK',
            accentColor: AppTheme.primaryBlue,
            onPressed: () => onCommand(RemoteCommand.back),
          ),

          // Home Button
          _ActionButtonItem(
            icon: Icons.home_rounded,
            label: 'HOME',
            accentColor: AppTheme.primaryCyan,
            onPressed: () => onCommand(RemoteCommand.home),
          ),

          // Play / Pause Button
          _ActionButtonItem(
            icon: Icons.play_arrow_rounded,
            label: 'PLAY',
            accentColor: AppTheme.accentGreen,
            onPressed: () => onCommand(RemoteCommand.playPause),
          ),
        ],
      ),
    );
  }
}

class _ActionButtonItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accentColor;
  final VoidCallback onPressed;

  const _ActionButtonItem({
    Key? key,
    required this.icon,
    required this.label,
    required this.accentColor,
    required this.onPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: const Color(0xFF202334),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: accentColor.withOpacity(0.4), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withOpacity(0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: Center(
                child: Icon(icon, color: accentColor, size: 24),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.bold,
            fontSize: 10,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
