import 'package:flutter/material.dart';
import '../services/google_tv_pairing_service.dart';
import '../theme/app_theme.dart';

enum _PairingState { connecting, waitingForPin, submitting, error }

class PinPairingDialog extends StatefulWidget {
  final String deviceName;
  final String ipAddress;
  final GoogleTvPairingService pairingService;
  final Function(PairingResult result) onPairingComplete;

  const PinPairingDialog({
    Key? key,
    required this.deviceName,
    required this.ipAddress,
    required this.pairingService,
    required this.onPairingComplete,
  }) : super(key: key);

  @override
  State<PinPairingDialog> createState() => _PinPairingDialogState();
}

class _PinPairingDialogState extends State<PinPairingDialog>
    with SingleTickerProviderStateMixin {
  final TextEditingController _pinController = TextEditingController();
  _PairingState _state = _PairingState.connecting;
  String _errorMessage = '';
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _startPairing();
  }

  @override
  void dispose() {
    _pinController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startPairing() async {
    setState(() {
      _state = _PairingState.connecting;
      _errorMessage = '';
    });

    // initiatePairing() opens mTLS on port 6467 and sends PairingRequest +
    // PairingOption + PairingConfiguration — this triggers the TV to display
    // the 6-digit PIN overlay on screen.
    final result = await widget.pairingService.initiatePairing(widget.ipAddress);

    if (!mounted) return;

    if (result.success) {
      setState(() {
        _state = _PairingState.waitingForPin;
        _pinController.clear();
      });
    } else {
      setState(() {
        _state = _PairingState.error;
        _errorMessage = result.message;
      });
    }
  }

  Future<void> _submitPin() async {
    final pin = _pinController.text.trim();
    if (pin.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter the PIN shown on your TV screen.';
      });
      return;
    }

    setState(() {
      _state = _PairingState.submitting;
      _errorMessage = '';
    });

    final result = await widget.pairingService.verifyPin(widget.ipAddress, pin);

    if (!mounted) return;

    if (result.success) {
      widget.onPairingComplete(result);
      Navigator.pop(context);
    } else {
      setState(() {
        // If PIN was wrong, go back to waitingForPin so user can re-enter
        _state = _PairingState.waitingForPin;
        _errorMessage = result.message.isNotEmpty
            ? result.message
            : 'Incorrect PIN. Please check your TV screen and try again.';
        _pinController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1B1F2D),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: AppTheme.primaryCyan.withOpacity(0.4), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    final color = _state == _PairingState.error
                        ? AppTheme.accentPowerRed
                        : AppTheme.primaryCyan;
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15 * _pulseAnimation.value),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: color.withOpacity(0.3 * _pulseAnimation.value),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      child: Icon(
                        _state == _PairingState.error
                            ? Icons.error_outline_rounded
                            : Icons.tv_rounded,
                        color: color,
                        size: 28,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pair with Google TV',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        widget.deviceName,
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // State-driven body
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: _buildBody(),
            ),

            const SizedBox(height: 20),

            // Action buttons
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      // ── CONNECTING ──────────────────────────────────────────────────────────
      case _PairingState.connecting:
        return Column(
          key: const ValueKey('connecting'),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.primaryCyan.withOpacity(0.07),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.primaryCyan.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryCyan),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Connecting to TV…',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Sending pairing request. A 6-digit PIN will appear on your TV screen.',
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 12, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

      // ── WAITING FOR PIN ──────────────────────────────────────────────────────
      case _PairingState.waitingForPin:
        return Column(
          key: const ValueKey('waitingForPin'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.accentGreen.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.accentGreen.withOpacity(0.35)),
              ),
              child: Row(
                children: const [
                  Icon(Icons.check_circle_outline_rounded, color: AppTheme.accentGreen, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'TV is showing a 6-digit PIN on screen!\nEnter it below to complete pairing.',
                      style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pinController,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              maxLength: 8,
              style: const TextStyle(
                color: AppTheme.primaryCyan,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: '● ● ● ● ● ●',
                hintStyle: TextStyle(
                  color: AppTheme.textMuted.withOpacity(0.4),
                  fontSize: 18,
                  letterSpacing: 6,
                ),
                filled: true,
                fillColor: AppTheme.surfaceDark,
                contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppTheme.primaryCyan.withOpacity(0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppTheme.primaryCyan, width: 2),
                ),
              ),
              onSubmitted: (_) => _submitPin(),
            ),
            if (_errorMessage.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.accentPowerRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: AppTheme.accentPowerRed, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage,
                        style: const TextStyle(
                          color: AppTheme.accentPowerRed,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );

      // ── SUBMITTING ───────────────────────────────────────────────────────────
      case _PairingState.submitting:
        return Container(
          key: const ValueKey('submitting'),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.primaryCyan.withOpacity(0.07),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: const [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryCyan),
                ),
              ),
              SizedBox(width: 14),
              Text(
                'Verifying PIN with TV…',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        );

      // ── ERROR ────────────────────────────────────────────────────────────────
      case _PairingState.error:
        return Container(
          key: const ValueKey('error'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.accentPowerRed.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.accentPowerRed.withOpacity(0.35)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.wifi_off_rounded, color: AppTheme.accentPowerRed, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage.isNotEmpty
                          ? _errorMessage
                          : 'Could not connect to TV.',
                      style: const TextStyle(color: Color(0xFFFF7F7F), fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(color: Colors.white10, height: 1),
              const SizedBox(height: 12),
              const Text(
                'Make sure your phone and TV are on the same Wi-Fi network, then tap Retry.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11, height: 1.4),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
    }
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: (_state == _PairingState.connecting || _state == _PairingState.submitting)
                ? null
                : () {
                    widget.pairingService.cancelPairing();
                    Navigator.pop(context);
                  },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted, fontSize: 14)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: _state == _PairingState.connecting || _state == _PairingState.submitting
                ? null
                : _state == _PairingState.error
                    ? _startPairing
                    : _submitPin,
            style: ElevatedButton.styleFrom(
              backgroundColor: _state == _PairingState.error
                  ? AppTheme.accentPowerRed
                  : AppTheme.primaryCyan,
              foregroundColor: Colors.black,
              disabledBackgroundColor: Colors.white10,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 4,
            ),
            child: Text(
              _state == _PairingState.error ? 'Retry' : 'Pair Remote',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }
}
