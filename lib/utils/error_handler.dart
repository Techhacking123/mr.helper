import 'package:flutter/material.dart';

/// Shows a user-friendly error dialog for network-related errors
void showNetworkErrorDialog(
  BuildContext context, {
  String? customMessage,
  VoidCallback? onRetry,
}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.wifi_off,
              color: Colors.orange.shade700,
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Connection Issue',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            customMessage ?? 'Unable to connect to the server.',
            style: const TextStyle(fontSize: 16, height: 1.4),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.blue.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Please check:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildCheckItem('✓ Your internet connection is active'),
                _buildCheckItem('✓ WiFi or mobile data is turned on'),
                _buildCheckItem('✓ You have network signal'),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: Colors.grey.shade600),
          child: const Text('Cancel', style: TextStyle(fontSize: 16)),
        ),
        ElevatedButton.icon(
          onPressed: () {
            Navigator.pop(context);
            if (onRetry != null) {
              onRetry();
            }
          },
          icon: const Icon(Icons.refresh, size: 20),
          label: const Text('Retry', style: TextStyle(fontSize: 16)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _buildCheckItem(String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
    ),
  );
}

/// Checks if an error is network-related
bool isNetworkError(dynamic error) {
  final errorString = error.toString().toLowerCase();
  return errorString.contains('network') ||
      errorString.contains('connection') ||
      errorString.contains('timeout') ||
      errorString.contains('socket') ||
      errorString.contains('handshake') ||
      errorString.contains('failed host lookup') ||
      errorString.contains('no internet');
}

/// Shows appropriate error message based on error type
void showErrorDialog(
  BuildContext context,
  dynamic error, {
  String? title,
  VoidCallback? onRetry,
}) {
  if (isNetworkError(error)) {
    showNetworkErrorDialog(context, onRetry: onRetry);
  } else {
    // Generic error dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title ?? 'Error',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Text(
          'Something went wrong. Please try again.',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}
