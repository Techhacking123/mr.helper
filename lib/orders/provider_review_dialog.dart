import 'package:flutter/material.dart';
import '../supabase_config.dart';
import '../auth/session_manager.dart';
import '../firebase/fcm_service.dart';

/// Dialog to collect user rating and review for a provider
class ProviderReviewDialog extends StatefulWidget {
  final String orderId;
  final String providerId;
  final String providerName;

  const ProviderReviewDialog({
    super.key,
    required this.orderId,
    required this.providerId,
    required this.providerName,
  });

  @override
  State<ProviderReviewDialog> createState() => _ProviderReviewDialogState();
}

class _ProviderReviewDialogState extends State<ProviderReviewDialog> {
  int _rating = 0;
  final _reviewController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  Future<void> _submitReview() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a rating'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final userId = await SessionManager.getUserId();
      if (userId == null) throw 'User not logged in';

      // Insert review
      await SupabaseConfig.supabase.from('provider_reviews').insert({
        'order_id': widget.orderId,
        'provider_id': widget.providerId,
        'user_id': userId,
        'rating': _rating,
        'review_text': _reviewController.text.trim().isEmpty
            ? null
            : _reviewController.text.trim(),
      });

      // Notify provider with push notification
      final reviewText = _reviewController.text.trim().isEmpty
          ? 'No comment'
          : _reviewController.text.trim();
      await FCMService.sendPushNotificationToUser(
        userId: widget.providerId,
        title: 'New Review Received!',
        message: 'You received a $_rating-star review! "$reviewText"',
        screen: 'order_detail',
        orderId: widget.orderId,
      );

      if (mounted) {
        Navigator.pop(
          context,
          true,
        ); // Return true to indicate review submitted
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error submitting review: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.star_rate_rounded,
                  size: 48,
                  color: Colors.amber.shade600,
                ),
              ),
              const SizedBox(height: 16),

              // Title
              const Text(
                'Rate Your Experience',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              // Provider Name
              Text(
                'How was your service with ${widget.providerName}?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),

              // Star Rating
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final starValue = index + 1;
                  return GestureDetector(
                    onTap: () => setState(() => _rating = starValue),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        starValue <= _rating
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 48,
                        color: starValue <= _rating
                            ? Colors.amber.shade600
                            : Colors.grey.shade300,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 8),

              // Rating Text
              if (_rating > 0)
                Text(
                  _getRatingText(_rating),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _getRatingColor(_rating),
                  ),
                )
              else
                Text(
                  'Tap to rate',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                ),
              const SizedBox(height: 24),

              // Review Text Field
              TextField(
                controller: _reviewController,
                maxLines: 4,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: 'Write a review (optional)',
                  hintText: 'Share details about your experience...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
              ),
              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  // Skip Button
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Skip'),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Submit Button
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitReview,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Submit Review',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getRatingText(int rating) {
    switch (rating) {
      case 5:
        return 'Excellent! ⭐';
      case 4:
        return 'Very Good! 👍';
      case 3:
        return 'Good 😊';
      case 2:
        return 'Fair 😐';
      case 1:
        return 'Poor 😞';
      default:
        return '';
    }
  }

  Color _getRatingColor(int rating) {
    if (rating >= 4) return Colors.green;
    if (rating >= 3) return Colors.orange;
    return Colors.red;
  }
}

/// Helper function to show the review dialog
Future<bool?> showProviderReviewDialog({
  required BuildContext context,
  required String orderId,
  required String providerId,
  required String providerName,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => ProviderReviewDialog(
      orderId: orderId,
      providerId: providerId,
      providerName: providerName,
    ),
  );
}
