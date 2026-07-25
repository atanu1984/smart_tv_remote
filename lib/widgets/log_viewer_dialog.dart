import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/app_logger.dart';

class LogViewerDialog extends StatefulWidget {
  const LogViewerDialog({Key? key}) : super(key: key);

  @override
  State<LogViewerDialog> createState() => _LogViewerDialogState();
}

class _LogViewerDialogState extends State<LogViewerDialog> {
  final ScrollController _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E222D),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Row(
            children: [
              Icon(Icons.terminal_rounded, color: Colors.cyanAccent, size: 22),
              SizedBox(width: 8),
              Text(
                'Diagnostic Logs',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.grey),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: StreamBuilder<String>(
          stream: AppLogger.logStream,
          builder: (context, snapshot) {
            final logs = AppLogger.logs;
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1117),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
              ),
              child: ListView.builder(
                controller: _scrollController,
                itemCount: logs.length,
                itemBuilder: (context, index) {
                  final log = logs[index];
                  bool isError = log.contains('Error') || log.contains('failed') || log.contains('402') || log.contains('92 03');
                  bool isSuccess = log.contains('SUCCESS') || log.contains('Paired') || log.contains('delivered') || log.contains('C8 01');

                  Color textColor = Colors.grey.shade300;
                  if (isError) textColor = Colors.redAccent;
                  if (isSuccess) textColor = Colors.greenAccent;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: SelectableText(
                      log,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            AppLogger.clear();
            setState(() {});
          },
          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
          label: const Text('Clear', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.cyanAccent.shade700,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            final text = AppLogger.getFormattedLogs();
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Logs copied to clipboard!')),
            );
          },
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('Copy Logs'),
        ),
      ],
    );
  }
}
