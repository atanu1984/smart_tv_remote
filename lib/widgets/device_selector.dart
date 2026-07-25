import 'package:flutter/material.dart';
import '../models/smart_tv_device.dart';
import '../models/network_state.dart';
import '../theme/app_theme.dart';

class DeviceSelectorHeader extends StatelessWidget {
  final NetworkState networkState;
  final SmartTvDevice? selectedDevice;
  final VoidCallback onOpenScanner;
  final Function(String newName) onRenameDevice;

  const DeviceSelectorHeader({
    Key? key,
    required this.networkState,
    required this.selectedDevice,
    required this.onOpenScanner,
    required this.onRenameDevice,
  }) : super(key: key);

  void _showRenameDialog(BuildContext context) {
    if (selectedDevice == null) return;

    final controller = TextEditingController(text: selectedDevice!.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.edit_note_rounded, color: AppTheme.primaryCyan),
            const SizedBox(width: 8),
            const Text('Rename Your TV', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Give your Smart TV a custom friendly name (e.g. "Dad\'s TV", "Living Room TV"):',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: const InputDecoration(
                hintText: 'Enter new TV name...',
                prefixIcon: Icon(Icons.tv_rounded, color: AppTheme.primaryCyan),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                onRenameDevice(newName);
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryCyan,
              foregroundColor: Colors.black,
            ),
            child: const Text('Save Name', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showTroubleshootingDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.help_outline_rounded, color: AppTheme.primaryCyan),
            SizedBox(width: 8),
            Text('TV Connection Setup Tips', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _TipItem(
                title: 'Android TV / Remote ATV Setup:',
                description: 'Go to Settings -> Device Preferences -> Developer Options -> Network Debugging / ADB Debugging and set it to ON. If a prompt appears on your TV screen asking to "Allow Debugging", select ALLOW.',
              ),
              SizedBox(height: 10),
              _TipItem(
                title: 'Roku TV Setup:',
                description: 'On your Roku remote, go to Settings -> System -> Advanced system settings -> Control by mobile apps, and set it to Default or Enabled.',
              ),
              SizedBox(height: 10),
              _TipItem(
                title: 'Samsung TV Setup:',
                description: 'Accept the "Allow Remote Connection" popup on your TV screen when connecting.',
              ),
              SizedBox(height: 10),
              _TipItem(
                title: 'LG webOS TV Setup:',
                description: 'Go to Settings -> Connection -> Mobile TV On / LG Connect Apps and set it to ON.',
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
            child: const Text('Got It'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: AppTheme.glassBoxDecoration(),
      child: Column(
        children: [
          // Wi-Fi Connection Bar
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: networkState.isConnectedToWifi ? AppTheme.accentGreen : AppTheme.accentPowerRed,
                  boxShadow: [
                    BoxShadow(
                      color: (networkState.isConnectedToWifi ? AppTheme.accentGreen : AppTheme.accentPowerRed)
                          .withOpacity(0.6),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                networkState.isConnectedToWifi ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                size: 18,
                color: networkState.isConnectedToWifi ? AppTheme.primaryCyan : AppTheme.textMuted,
              ),
              const SizedBox(width: 8),
              Text(
                networkState.isConnectedToWifi
                    ? (networkState.wifiSsid ?? 'Wi-Fi Connected')
                    : 'No Wi-Fi Connection',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
              ),
              const Spacer(),
              // Help Button
              IconButton(
                icon: const Icon(Icons.help_outline_rounded, color: AppTheme.textMuted, size: 20),
                onPressed: () => _showTroubleshootingDialog(context),
                tooltip: 'TV Setup Troubleshooting',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(color: Color(0x1AFFFFFF), height: 1),
          const SizedBox(height: 12),

          // Active Smart TV Device Card
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryCyan.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    _getBrandIcon(selectedDevice?.brand),
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            selectedDevice?.name ?? 'No TV Connected',
                            style: Theme.of(context).textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (selectedDevice != null) ...[
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => _showRenameDialog(context),
                            borderRadius: BorderRadius.circular(6),
                            child: const Padding(
                              padding: EdgeInsets.all(2),
                              child: Icon(Icons.edit_rounded, color: AppTheme.primaryCyan, size: 16),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      selectedDevice != null
                          ? '${selectedDevice!.brand.displayName} • ${selectedDevice!.ipAddress}'
                          : 'Tap scan to discover TVs on your Wi-Fi',
                      style: Theme.of(context).textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Scan / Change TV Button
              InkWell(
                onTap: onOpenScanner,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.radar_rounded, color: AppTheme.primaryCyan, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Scan',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.primaryCyan,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _getBrandIcon(TvBrand? brand) {
    if (brand == null) return Icons.tv_rounded;
    switch (brand) {
      case TvBrand.roku:
        return Icons.tv_rounded;
      case TvBrand.samsung:
        return Icons.live_tv_rounded;
      case TvBrand.lg:
        return Icons.connected_tv_rounded;
      case TvBrand.androidTv:
        return Icons.android_rounded;
      case TvBrand.tcl:
        return Icons.cast_rounded;
      case TvBrand.genericDial:
        return Icons.cast_connected_rounded;
    }
  }
}

class _TipItem extends StatelessWidget {
  final String title;
  final String description;

  const _TipItem({Key? key, required this.title, required this.description}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: AppTheme.primaryCyan, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 2),
        Text(description, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      ],
    );
  }
}
