import 'package:flutter/material.dart';
import '../supabase_config.dart';
import '../auth/session_manager.dart';

class ReportModal extends StatefulWidget {
  final String reportedProfileId;

  const ReportModal({super.key, required this.reportedProfileId});

  @override
  State<ReportModal> createState() => _ReportModalState();
}

class _ReportModalState extends State<ReportModal> {
  final _otherController = TextEditingController();
  bool _isLoading = false;
  String? _selectedReason;

  final List<String> _reportReasons = [
    'Inappropriate Content',
    'Spam or Scam',
    'Fake Profile',
    'Harassment',
    'Offensive Behavior',
    'Other',
  ];

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  Future<void> _submitReport() async {
    if (_selectedReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a reason for reporting.')),
      );
      return;
    }

    final reasonText = _selectedReason == 'Other'
        ? _otherController.text.trim()
        : _selectedReason!;

    if (reasonText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide details for the report.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final userId = await SessionManager.getUserId();
      if (userId == null) {
        if (mounted) Navigator.pop(context);
        return;
      }

      await SupabaseConfig.supabase.from('reports').insert({
        'reporter_id': userId,
        'reported_id': widget.reportedProfileId,
        'reason': reasonText,
        // 'created_at': DateTime.now().toIso8601String(), // Usually handled by DB default
      });

      if (mounted) {
        Navigator.pop(context);
        _showSuccessDialog();
      }
    } catch (e) {
      debugPrint('Error reporting profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Column(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 50),
            SizedBox(height: 10),
            Text('Report Submitted'),
          ],
        ),
        content: const Text(
          'Thank you for keeping our community safe. We will review the report shortly.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle Bar
          Center(
            child: Container(
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.flag_rounded,
                  color: Colors.red,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Report User',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      'This helps us keep the community safe.',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Reason Selection
          const Text(
            'Why are you reporting this user?',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _reportReasons.map((reason) {
              final isSelected = _selectedReason == reason;
              return ChoiceChip(
                label: Text(reason),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _selectedReason = selected ? reason : null;
                  });
                },
                selectedColor: Colors.red.shade100,
                backgroundColor: Colors.grey.shade100,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.red.shade900 : Colors.black87,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: isSelected
                        ? Colors.red.shade200
                        : Colors.grey.shade200,
                  ),
                ),
              );
            }).toList(),
          ),

          // Optional Description (Shown if needed, or always)
          if (_selectedReason != null) ...[
            const SizedBox(height: 20),
            TextField(
              controller: _otherController,
              maxLines: _selectedReason == 'Other' ? 3 : 2,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey.shade50,
                hintText: _selectedReason == 'Other'
                    ? 'Please tell us more details...'
                    : 'Any additional comments? (Optional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ],

          const SizedBox(height: 32),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    foregroundColor: Colors.grey.shade700,
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitReport,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Submit Report',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
