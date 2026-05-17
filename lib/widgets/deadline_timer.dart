import 'dart:async';
import 'package:flutter/material.dart';

/// Widget that displays a countdown timer until order deadline
class DeadlineTimer extends StatefulWidget {
  final DateTime deadline;
  final VoidCallback? onExpired;
  final bool showIcon;
  final bool compact;

  const DeadlineTimer({
    super.key,
    required this.deadline,
    this.onExpired,
    this.showIcon = true,
    this.compact = false,
  });

  @override
  State<DeadlineTimer> createState() => _DeadlineTimerState();
}

class _DeadlineTimerState extends State<DeadlineTimer> {
  Timer? _timer;
  Duration _remaining = Duration.zero;
  bool _isExpired = false;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateRemaining();
    });
  }

  void _updateRemaining() {
    final now = DateTime.now();
    final remaining = widget.deadline.difference(now);

    if (remaining.isNegative && !_isExpired) {
      setState(() {
        _remaining = Duration.zero;
        _isExpired = true;
      });
      widget.onExpired?.call();
    } else if (!remaining.isNegative) {
      setState(() {
        _remaining = remaining;
        _isExpired = false;
      });
    }
  }

  String _formatTime() {
    if (_isExpired) return 'EXPIRED';

    final hours = _remaining.inHours;
    final minutes = _remaining.inMinutes % 60;
    final seconds = _remaining.inSeconds % 60;

    if (hours > 24) {
      final days = (hours / 24).floor();
      final remainingHours = hours % 24;
      return '${days}d ${remainingHours}h ${minutes}m';
    } else if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else {
      return '${minutes}m ${seconds}s';
    }
  }

  Color _getTimerColor() {
    if (_isExpired) return Colors.red;
    if (_remaining.inHours < 2) return Colors.orange;
    if (_remaining.inHours < 6) return Colors.amber;
    return Colors.green;
  }

  IconData _getTimerIcon() {
    if (_isExpired) return Icons.error;
    if (_remaining.inHours < 2) return Icons.warning_amber;
    return Icons.schedule;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return _buildCompactTimer();
    } else {
      return _buildFullTimer();
    }
  }

  Widget _buildCompactTimer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getTimerColor().withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _getTimerColor(), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showIcon) ...[
            Icon(_getTimerIcon(), color: _getTimerColor(), size: 14),
            const SizedBox(width: 4),
          ],
          Text(
            _formatTime(),
            style: TextStyle(
              color: _getTimerColor(),
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFullTimer() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _getTimerColor().withOpacity(0.1),
            _getTimerColor().withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _getTimerColor(), width: 2),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_getTimerIcon(), color: _getTimerColor(), size: 28),
              const SizedBox(width: 12),
              Text(
                _isExpired ? 'DEADLINE PASSED' : 'Time Remaining',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _getTimerColor(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: _getTimerColor().withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              _formatTime(),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: _getTimerColor(),
                letterSpacing: 1.2,
              ),
            ),
          ),
          if (!_isExpired) ...[
            const SizedBox(height: 8),
            Text(
              'Deadline: ${_formatDeadline()}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDeadline() {
    final deadline = widget.deadline;
    final now = DateTime.now();

    // If deadline is today
    if (deadline.year == now.year &&
        deadline.month == now.month &&
        deadline.day == now.day) {
      return 'Today at ${_formatTime12Hour(deadline)}';
    }

    // If deadline is tomorrow
    final tomorrow = now.add(const Duration(days: 1));
    if (deadline.year == tomorrow.year &&
        deadline.month == tomorrow.month &&
        deadline.day == tomorrow.day) {
      return 'Tomorrow at ${_formatTime12Hour(deadline)}';
    }

    // Otherwise show full date
    return '${deadline.day}/${deadline.month}/${deadline.year} at ${_formatTime12Hour(deadline)}';
  }

  String _formatTime12Hour(DateTime time) {
    final hour = time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$hour12:$minute $period';
  }
}
