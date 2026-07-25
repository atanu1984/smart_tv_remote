import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'tv_remote_controller.dart';

class VoiceCommandIntent {
  final RemoteCommand? command;
  final String? movieSearchQuery;
  final String rawSpokenText;

  const VoiceCommandIntent({
    this.command,
    this.movieSearchQuery,
    required this.rawSpokenText,
  });

  bool get isValid => command != null || (movieSearchQuery != null && movieSearchQuery!.isNotEmpty);
}

class SpeechService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;

  /// Initializes the microphone speech recognition engine
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    try {
      _isInitialized = await _speech.initialize(
        onError: (_) {},
        onStatus: (_) {},
      );
      return _isInitialized;
    } catch (_) {
      return false;
    }
  }

  /// Listens to microphone audio and streams recognized voice text
  Future<void> startListening({
    required Function(String recognizedText) onResult,
    required Function(VoiceCommandIntent intent) onCommandRecognized,
    required VoidCallback onDone,
  }) async {
    final available = await initialize();
    if (!available) {
      onResult('Microphone not available or permission denied.');
      onDone();
      return;
    }

    _speech.listen(
      onResult: (result) {
        final text = result.recognizedWords;
        onResult(text);

        if (result.finalResult && text.trim().isNotEmpty) {
          final intent = parseVoiceIntent(text);
          onCommandRecognized(intent);
          stopListening();
          onDone();
        }
      },
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 2),
      cancelOnError: true,
      partialResults: true,
    );
  }

  /// Stops microphone recording
  Future<void> stopListening() async {
    try {
      await _speech.stop();
    } catch (_) {}
  }

  bool get isListening => _speech.isListening;

  /// Intelligent Voice Intent Parser
  VoiceCommandIntent parseVoiceIntent(String spokenText) {
    final lower = spokenText.toLowerCase().trim();

    // MUTE / UNMUTE
    if (lower.contains('mute') || lower.contains('unmute') || lower.contains('silence')) {
      return VoiceCommandIntent(command: RemoteCommand.volumeMute, rawSpokenText: spokenText);
    }

    // VOLUME UP / LOUDER
    if (lower.contains('volume up') || lower.contains('louder') || lower.contains('turn up') || lower.contains('increase volume')) {
      return VoiceCommandIntent(command: RemoteCommand.volumeUp, rawSpokenText: spokenText);
    }

    // VOLUME DOWN / QUIETER
    if (lower.contains('volume down') || lower.contains('quieter') || lower.contains('turn down') || lower.contains('decrease volume') || lower.contains('lower volume')) {
      return VoiceCommandIntent(command: RemoteCommand.volumeDown, rawSpokenText: spokenText);
    }

    // HOME
    if (lower.contains('home') || lower.contains('main menu') || lower.contains('go home')) {
      return VoiceCommandIntent(command: RemoteCommand.home, rawSpokenText: spokenText);
    }

    // BACK
    if (lower.contains('back') || lower.contains('go back') || lower.contains('return')) {
      return VoiceCommandIntent(command: RemoteCommand.back, rawSpokenText: spokenText);
    }

    // POWER
    if (lower.contains('power') || lower.contains('turn off') || lower.contains('switch off') || lower.contains('shutdown')) {
      return VoiceCommandIntent(command: RemoteCommand.power, rawSpokenText: spokenText);
    }

    // PLAY / PAUSE
    if (lower == 'play' || lower == 'pause' || lower.contains('play pause') || lower.contains('resume')) {
      return VoiceCommandIntent(command: RemoteCommand.playPause, rawSpokenText: spokenText);
    }

    // OK / SELECT
    if (lower == 'ok' || lower == 'select' || lower == 'enter' || lower == 'choose') {
      return VoiceCommandIntent(command: RemoteCommand.select, rawSpokenText: spokenText);
    }

    // SEARCH / MOVIE CASTING INTENTS
    final searchPrefixes = ['search for', 'search', 'play', 'find', 'watch', 'look for', 'cast'];
    for (final prefix in searchPrefixes) {
      if (lower.startsWith(prefix)) {
        final query = spokenText.substring(prefix.length).trim();
        if (query.isNotEmpty) {
          return VoiceCommandIntent(movieSearchQuery: query, rawSpokenText: spokenText);
        }
      }
    }

    // Fallback: If non-empty speech didn't match system commands, treat as movie search
    return VoiceCommandIntent(movieSearchQuery: spokenText.trim(), rawSpokenText: spokenText);
  }
}
