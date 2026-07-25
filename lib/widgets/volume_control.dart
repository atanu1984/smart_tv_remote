import 'package:flutter/material.dart';
import '../services/tv_remote_controller.dart';
import '../theme/app_theme.dart';

class VolumeControlWidget extends StatefulWidget {
  final Function(RemoteCommand command) onCommand;

  const VolumeControlWidget({
    Key? key,
    required this.onCommand,
  }) : super(key: key);

  @override
  State<VolumeControlWidget> createState() => _VolumeControlWidgetState();
}

class _VolumeControlWidgetState extends State<VolumeControlWidget> {
  bool _isMuted = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: AppTheme.glassBoxDecoration(borderRadius: 24),
      child: Column(
        children: [
          Text(
            'VOLUME',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  fontSize: 11,
                  color: AppTheme.textMuted,
                ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Volume Down (-)
              _VolumeButton(
                icon: Icons.remove_rounded,
                label: 'VOL -',
                onPressed: () => widget.onCommand(RemoteCommand.volumeDown),
              ),

              // Mute Toggle Button
              _VolumeButton(
                icon: _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                label: _isMuted ? 'UNMUTE' : 'MUTE',
                isHighlighted: _isMuted,
                activeColor: AppTheme.accentPowerRed,
                onPressed: () {
                  setState(() {
                    _isMuted = !_isMuted;
                  });
                  widget.onCommand(RemoteCommand.volumeMute);
                },
              ),

              // Volume Up (+)
              _VolumeButton(
                icon: Icons.add_rounded,
                label: 'VOL +',
                activeColor: AppTheme.primaryCyan,
                onPressed: () => widget.onCommand(RemoteCommand.volumeUp),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VolumeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool isHighlighted;
  final Color? activeColor;

  const _VolumeButton({
    Key? key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isHighlighted = false,
    this.activeColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final color = isHighlighted
        ? (activeColor ?? AppTheme.primaryCyan)
        : AppTheme.textPrimary;

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: isHighlighted
                    ? (activeColor ?? AppTheme.primaryCyan).withOpacity(0.2)
                    : const Color(0xFF222638),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isHighlighted
                      ? (activeColor ?? AppTheme.primaryCyan)
                      : const Color(0x33FFFFFF),
                  width: 1.5,
                ),
                boxShadow: isHighlighted
                    ? [
                        BoxShadow(
                          color: (activeColor ?? AppTheme.primaryCyan).withOpacity(0.4),
                          blurRadius: 10,
                        )
                      ]
                    : null,
              ),
              child: Center(
                child: Icon(icon, color: color, size: 26),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 10,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}
