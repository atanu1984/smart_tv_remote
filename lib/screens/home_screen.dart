import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/smart_tv_device.dart';
import '../models/network_state.dart';
import '../services/wifi_service.dart';
import '../services/network_discovery_service.dart';
import '../services/tv_remote_controller.dart';
import '../widgets/device_selector.dart';
import '../widgets/search_cast_bar.dart';
import '../widgets/dpad_widget.dart';
import '../widgets/volume_control.dart';
import '../widgets/action_buttons.dart';
import '../theme/app_theme.dart';
import '../widgets/pin_pairing_dialog.dart';
import 'scanner_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final WifiService _wifiService = WifiService();
  final NetworkDiscoveryService _discoveryService = NetworkDiscoveryService();
  final TvRemoteController _remoteController = TvRemoteController();

  NetworkState _networkState = const NetworkState();
  SmartTvDevice? _selectedDevice;

  @override
  void initState() {
    super.initState();
    _initializeConnectivityAndDevices();
  }

  Future<void> _initializeConnectivityAndDevices() async {
    final netState = await _wifiService.checkWifiStatus();
    if (mounted) {
      setState(() {
        _networkState = netState;
      });
    }

    final prefix = netState.subnetPrefix ?? '192.168.1';
    final demoDevices = _discoveryService.getDemoDevices(prefix);

    if (mounted && _selectedDevice == null && demoDevices.isNotEmpty) {
      final initialDevice = demoDevices.first;
      final savedName = await _getSavedCustomName(initialDevice.id);

      setState(() {
        _selectedDevice = savedName != null
            ? initialDevice.copyWith(customName: savedName)
            : initialDevice;
      });
    }
  }

  Future<String?> _getSavedCustomName(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('custom_name_$deviceId');
    } catch (_) {
      return null;
    }
  }

  void _handleRenameDevice(String newName) async {
    if (_selectedDevice == null) return;

    final updatedDevice = _selectedDevice!.copyWith(customName: newName);
    setState(() {
      _selectedDevice = updatedDevice;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('custom_name_${_selectedDevice!.id}', newName);
    } catch (_) {}

    _showFeedbackSnackBar('TV renamed to "$newName"');
  }

  void _showPinPairingDialog(String ipAddress, {String? deviceName}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PinPairingDialog(
        deviceName: deviceName ?? _selectedDevice?.name ?? ipAddress,
        ipAddress: ipAddress,
        pairingService: _remoteController.pairingService,
        onPairingComplete: (pairingResult) {
          _showFeedbackSnackBar(pairingResult.message);
        },
      ),
    );
  }

  Future<void> _unpairCurrentDevice() async {
    if (_selectedDevice == null) return;
    final ip = _selectedDevice!.ipAddress;
    final name = _selectedDevice!.name;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2235),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.link_off_rounded, color: Color(0xFFFF5C5C), size: 22),
            SizedBox(width: 10),
            Text('Remove Pairing', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Remove the pairing for $name?\n\nYou will need to enter a new PIN next time you connect.',
          style: const TextStyle(color: Color(0xFFB0B8D1), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7594))),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_rounded, size: 16),
            label: const Text('Remove'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5C5C),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _remoteController.pairingService.unpairDevice(ip);
      _showFeedbackSnackBar('Pairing removed for $name. Reconnect to pair again.');
    }
  }

  void _handleRemoteCommand(RemoteCommand command) async {
    if (_selectedDevice == null) {
      _showFeedbackSnackBar('Please select a Smart TV first.', isError: true);
      return;
    }

    final result = await _remoteController.sendCommand(
      device: _selectedDevice!,
      command: command,
    );

    if (result.needsPairing && result.pairingIp != null) {
      _showPinPairingDialog(result.pairingIp!);
    } else {
      _showFeedbackSnackBar(result.message, isError: !result.success);
    }
  }

  void _handleMovieCast(String movieTitle) async {
    if (_selectedDevice == null) {
      _showFeedbackSnackBar('Please select a Smart TV first.', isError: true);
      return;
    }

    final result = await _remoteController.castMovieOrText(
      device: _selectedDevice!,
      textQuery: movieTitle,
    );

    _showFeedbackSnackBar(result.message, isError: !result.success);
  }

  void _showFeedbackSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
              color: isError ? AppTheme.accentPowerRed : AppTheme.accentGreen,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: isError ? const Color(0xFFFFD1D1) : Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? const Color(0xFF2C1C24) : const Color(0xFF1E2235),
        duration: Duration(seconds: isError ? 4 : 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: isError ? AppTheme.accentPowerRed.withOpacity(0.5) : Colors.transparent,
            width: 1,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  void _openScannerModal() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScannerScreen(
          networkState: _networkState,
          currentDevice: _selectedDevice,
          onSelectDevice: (device) async {
            final savedName = await _getSavedCustomName(device.id);
            final activeDevice = savedName != null ? device.copyWith(customName: savedName) : device;

            setState(() {
              _selectedDevice = activeDevice;
            });

            // Check if Google TV / TCL TV needs PIN pairing
            if (device.brand == TvBrand.tcl || device.brand == TvBrand.androidTv || device.brand == TvBrand.genericDial) {
              final isPaired = await _remoteController.pairingService.isDevicePaired(device.ipAddress);
              if (!isPaired) {
                _showPinPairingDialog(device.ipAddress, deviceName: device.name);
                return;
              }
            }

            _showFeedbackSnackBar('Connected to ${activeDevice.name}');
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Title Bar
              Row(
                children: [
                  const Icon(Icons.settings_remote_rounded, color: AppTheme.primaryCyan, size: 28),
                  const SizedBox(width: 10),
                  Text(
                    'Smart TV Remote',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  if (_selectedDevice != null)
                    IconButton(
                      icon: const Icon(Icons.pin_rounded, color: AppTheme.accentGreen),
                      onPressed: () => _showPinPairingDialog(_selectedDevice!.ipAddress),
                      tooltip: 'Pair TV (Show PIN on TV screen)',
                    ),
                  if (_selectedDevice != null)
                    IconButton(
                      icon: const Icon(Icons.link_off_rounded, color: Color(0xFFFF5C5C)),
                      onPressed: _unpairCurrentDevice,
                      tooltip: 'Remove pairing (reconnect with new PIN)',
                    ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: AppTheme.primaryCyan),
                    onPressed: _initializeConnectivityAndDevices,
                    tooltip: 'Refresh Wi-Fi state',
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Wi-Fi & Selected Device Header (with TV rename button)
              DeviceSelectorHeader(
                networkState: _networkState,
                selectedDevice: _selectedDevice,
                onOpenScanner: _openScannerModal,
                onRenameDevice: _handleRenameDevice,
              ),

              const SizedBox(height: 16),

              // Search & Movie Cast Bar
              SearchCastBar(
                onCast: _handleMovieCast,
                isConnected: _selectedDevice != null,
              ),

              const SizedBox(height: 16),

              // Action Buttons Row (Power, Back, Home, Play)
              ActionButtonsWidget(
                onCommand: _handleRemoteCommand,
              ),

              const SizedBox(height: 20),

              // D-Pad Tactical Ring
              DPadWidget(
                onCommand: _handleRemoteCommand,
              ),

              const SizedBox(height: 20),

              // Volume Rocker Controls
              VolumeControlWidget(
                onCommand: _handleRemoteCommand,
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
