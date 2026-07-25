import 'package:flutter/material.dart';
import '../services/speech_service.dart';
import '../theme/app_theme.dart';

class VoiceRemoteWidget extends StatefulWidget {
  final Function(VoiceCommandIntent intent) onVoiceCommand;
  final bool isConnected;

  const VoiceRemoteWidget({
    Key? key,
    required this.onVoiceCommand,
    required this.isConnected,
  }) : super(key: key);

  @override
  State<VoiceRemoteWidget> createState() => _VoiceRemoteWidgetState();
}

class _VoiceRemoteWidgetState extends State<VoiceRemoteWidget> with SingleTickerProviderStateMixin {
  final SpeechService _speechService = SpeechService();
  late AnimationController _pulseController;

  bool _isListening = false;
  String _liveSpokenText = '';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _toggleListening() async {
    if (_isListening) {
      await _speechService.stopListening();
      _pulseController.stop();
      setState(() {
        _isListening = false;
      });
    } else {
      setState(() {
        _isListening = true;
        _liveSpokenText = 'Listening... Speak your command...';
      });
      _pulseController.repeat(reverse: true);

      await _speechService.startListening(
        onResult: (text) {
          if (mounted) {
            setState(() {
              _liveSpokenText = text.isEmpty ? 'Listening...' : '"$text"';
            });
          }
        },
        onCommandRecognized: (intent) {
          if (mounted) {
            widget.onVoiceCommand(intent);
          }
        },
        onDone: () {
          if (mounted) {
            _pulseController.stop();
            setState(() {
              _isListening = false;
            });
          }
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: AppTheme.glassBoxDecoration(borderRadius: 20),
      child: Column(
        children: [
          Row(
            children: [
              // Microphone Glowing Button
              GestureDetector(
                onTap: widget.isConnected ? _toggleListening : null,
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    final pulseOpacity = _isListening ? 0.3 + (_pulseController.value * 0.4) : 0.2;
                    final iconColor = _isListening ? AppTheme.accentPowerRed : AppTheme.primaryCyan;

                    return Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: iconColor.withOpacity(pulseOpacity),
                        border: Border.all(color: iconColor, width: _isListening ? 2 : 1),
                        boxShadow: _isListening
                            ? [
                                BoxShadow(
                                  color: AppTheme.accentPowerRed.withOpacity(0.6),
                                  blurRadius: 16,
                                  spreadRadius: 3,
                                )
                              ]
                            : null,
                      ),
                      child: Icon(
                        _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 14),

              // Voice Status & Instructions
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isListening ? 'Voice Remote Active' : 'Tap Mic for Voice Control',
                      style: TextStyle(
                        color: _isListening ? AppTheme.accentPowerRed : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _liveSpokenText.isNotEmpty
                          ? _liveSpokenText
                          : 'Say "Mute", "Volume Up", "Home", or "Search Inception"',
                      style: TextStyle(
                        color: _isListening ? AppTheme.primaryCyan : AppTheme.textMuted,
                        fontSize: 11,
                        fontStyle: _isListening ? FontStyle.italic : FontStyle.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              if (_isListening)
                TextButton(
                  onPressed: _toggleListening,
                  child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
