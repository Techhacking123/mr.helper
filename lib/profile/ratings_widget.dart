import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';

import '../supabase_config.dart';
import '../auth/session_manager.dart';
import '../widgets/safe_network_image.dart';

class RatingsWidget extends StatefulWidget {
  final String profileId;
  final bool isOwner;

  const RatingsWidget({
    super.key,
    required this.profileId,
    required this.isOwner,
  });

  @override
  State<RatingsWidget> createState() => _RatingsWidgetState();
}

class _RatingsWidgetState extends State<RatingsWidget> {
  List<Map<String, dynamic>> _reviews = [];
  bool _isLoading = true;
  String? _currentUserId;

  // My Review Logic
  bool _hasRated = false;
  Map<String, dynamic>? _myReview;

  late RealtimeChannel _channel;

  @override
  void initState() {
    super.initState();
    _fetchReviews();
    _setupRealtime();
  }

  void _setupRealtime() {
    _channel = SupabaseConfig.supabase
        .channel('public:provider_reviews:profile')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'provider_reviews',
          callback: (payload) {
            _fetchReviews();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    SupabaseConfig.supabase.removeChannel(_channel);
    super.dispose();
  }

  Future<void> _fetchReviews() async {
    try {
      _currentUserId = await SessionManager.getUserId();

      // Fetch reviews with reviewer details
      final response = await SupabaseConfig.supabase
          .from('provider_reviews')
          .select('*, reviewer:users!user_id(full_name, avatar_url)')
          .eq('provider_id', widget.profileId)
          .order('created_at', ascending: false);

      final List<Map<String, dynamic>> data = List<Map<String, dynamic>>.from(
        response,
      );

      // Check if I rated
      Map<String, dynamic>? myReview;
      if (_currentUserId != null) {
        try {
          myReview = data.firstWhere((f) => f['user_id'] == _currentUserId);
          _hasRated = true;
        } catch (e) {
          _hasRated = false;
        }
      }

      setState(() {
        _reviews = data;
        _myReview = myReview;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching reviews: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitReview(double rating, String comment) async {
    if (_currentUserId == null) return;
    try {
      // Submit review directly from profile (order_id will be null)
      await SupabaseConfig.supabase.from('provider_reviews').insert({
        'user_id': _currentUserId,
        'provider_id': widget.profileId,
        'order_id': null, // No order - direct profile review
        'rating': rating.toInt(),
        'review_text': comment.trim().isEmpty ? null : comment.trim(),
      });

      // Notify provider
      await SupabaseConfig.supabase.from('notifications').insert({
        'user_id': widget.profileId,
        'message':
            'You received a ${rating.toInt()}-star review from a customer!',
        'is_read': false,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Review submitted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }

      _fetchReviews(); // Refresh
    } catch (e) {
      debugPrint('Error submit review: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error: ${e.toString().contains("duplicate") ? "You have already reviewed this provider" : e.toString()}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteReview(String reviewId) async {
    try {
      await SupabaseConfig.supabase
          .from('provider_reviews')
          .delete()
          .eq('id', reviewId);
      _fetchReviews(); // Refresh
    } catch (e) {
      debugPrint('Delete error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  Future<void> _submitReply(String reviewId, String replyObj) async {
    try {
      // Replies are not supported in provider_reviews table
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Replies not currently supported')),
      );
      return;
    } catch (e) {
      debugPrint('Reply error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            'Reviews & Ratings',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),

        // Add Review Section (Only if not owner and hasn't rated)
        if (!widget.isOwner && !_hasRated && _currentUserId != null)
          _AddReviewForm(onSubmit: _submitReview),

        // My Review Section (If has rated)
        if (_hasRated && _myReview != null)
          _MyReviewCard(
            review: _myReview!,
            onDelete: () => _deleteReview(_myReview!['id']),
          ),

        const Divider(),

        if (_reviews.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No reviews yet. Be the first!'),
          ),

        // List of Reviews
        ..._reviews.where((f) => f['user_id'] != _currentUserId).map((f) {
          return _ReviewCard(
            review: f,
            isOwner: widget.isOwner,
            onReply: (text) => _submitReply(f['id'], text),
          );
        }).toList(),
      ],
    );
  }
}

class _AddReviewForm extends StatefulWidget {
  final Function(double, String) onSubmit;
  const _AddReviewForm({required this.onSubmit});

  @override
  State<_AddReviewForm> createState() => _AddReviewFormState();
}

class _AddReviewFormState extends State<_AddReviewForm> {
  double _rating = 5;
  final _commentController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            const Text(
              'Write a Review',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            RatingBar.builder(
              initialRating: 5,
              minRating: 1,
              direction: Axis.horizontal,
              itemCount: 5,
              itemSize: 24,
              itemBuilder: (context, _) =>
                  const Icon(Icons.star, color: Colors.amber),
              onRatingUpdate: (rating) => _rating = rating,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _commentController,
              decoration: const InputDecoration(
                hintText: 'Share your experience...',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.all(8),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () =>
                  widget.onSubmit(_rating, _commentController.text),
              child: const Text('Submit Review'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyReviewCard extends StatelessWidget {
  final Map<String, dynamic> review;
  final VoidCallback onDelete;

  const _MyReviewCard({required this.review, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.green.shade50,
      child: ListTile(
        title: const Text(
          'Your Review',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RatingBarIndicator(
              rating: (review['rating'] as int).toDouble(),
              itemBuilder: (context, index) =>
                  const Icon(Icons.star, color: Colors.amber),
              itemCount: 5,
              itemSize: 16.0,
            ),
            Text(review['review_text'] ?? ''),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: onDelete,
        ),
      ),
    );
  }
}

class _ReviewCard extends StatefulWidget {
  final Map<String, dynamic> review;
  final bool isOwner;
  final Function(String) onReply;

  const _ReviewCard({
    required this.review,
    required this.isOwner,
    required this.onReply,
  });

  @override
  State<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<_ReviewCard> {
  bool _isReplying = false;
  final _replyController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final reviewer = widget.review['reviewer'] ?? {};
    final fullName = reviewer['full_name'] ?? 'Unknown User';
    final avatarUrl = reviewer['avatar_url'];
    final reply = widget.review['reply'];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SafeAvatar(imageUrl: avatarUrl, radius: 16, userName: fullName),
                const SizedBox(width: 8),
                Text(
                  fullName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  widget.review['created_at']?.toString().substring(0, 10) ??
                      '',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 4),
            RatingBarIndicator(
              rating: (widget.review['rating'] as int).toDouble(),
              itemBuilder: (context, index) =>
                  const Icon(Icons.star, color: Colors.amber),
              itemCount: 5,
              itemSize: 16.0,
            ),
            const SizedBox(height: 4),
            Text(widget.review['review_text'] ?? ''),

            // Reply Section
            if (reply != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  border: Border(
                    left: BorderSide(color: Colors.blue.shade300, width: 3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Response from Provider:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    Text(reply, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ],

            // Add Reply Button (Owner only, no existing reply)
            if (widget.isOwner && reply == null) ...[
              if (_isReplying) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _replyController,
                  decoration: const InputDecoration(
                    hintText: 'Write a reply...',
                    contentPadding: EdgeInsets.all(8),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _isReplying = false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        widget.onReply(_replyController.text);
                        setState(() => _isReplying = false);
                      },
                      child: const Text('Post Reply'),
                    ),
                  ],
                ),
              ] else
                TextButton(
                  onPressed: () => setState(() => _isReplying = true),
                  child: const Text('Reply'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
