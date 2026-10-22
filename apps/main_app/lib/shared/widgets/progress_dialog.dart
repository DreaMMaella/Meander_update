import 'package:flutter/material.dart';

class ProgressDialog extends StatefulWidget {
  final String initialMessage;
  final double? initialProgress;
  final bool showProgressIndicator;

  const ProgressDialog({
    Key? key,
    required this.initialMessage,
    this.initialProgress,
    this.showProgressIndicator = true,
  }) : super(key: key);

  @override
  State<ProgressDialog> createState() => ProgressDialogState();
}

class ProgressDialogState extends State<ProgressDialog> {
  late String _message;
  late double? _progress;

  @override
  void initState() {
    super.initState();
    _message = widget.initialMessage;
    _progress = widget.initialProgress;
  }

  void updateProgress(String message, {double? progress}) {
    if (mounted) {
      setState(() {
        _message = message;
        if (progress != null) {
          _progress = progress;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF2A2A2A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.showProgressIndicator)
              _progress != null
                  ? LinearProgressIndicator(
                      value: _progress!,
                      backgroundColor: Colors.grey[800],
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF00C853),
                      ),
                    )
                  : const CircularProgressIndicator(color: Color(0xFF00C853))
            else
              const Icon(Icons.sync, color: Color(0xFF00C853), size: 40),
            const SizedBox(height: 24),
            Text(
              _message,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class ProgressDialogController {
  final ProgressDialogState state;

  ProgressDialogController(this.state);

  void updateProgress(String message, {double? progress}) {
    state.updateProgress(message, progress: progress);
  }
}
