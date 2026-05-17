import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_config.dart';

class OrderChatPage extends StatefulWidget {
  final String orderId;
  final String orderTitle;
  final bool isProvider;
  final String userId;

  const OrderChatPage({
    super.key,
    required this.orderId,
    required this.orderTitle,
    required this.isProvider,
    required this.userId,
  });

  @override
  State<OrderChatPage> createState() => _OrderChatPageState();
}

class _OrderChatPageState extends State<OrderChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String? _sessionId;
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  String? _error;
  RealtimeChannel? _messageSubscription;

  // Predefined quick reply messages for Users
  static const List<String> _userQuickReplies = [
    'Hi! I need your service',
    'Are you available today?',
    'What is your price?',
    'Can you come to my location?',
    'How long will it take?',
    'Please share your contact number',
    'I will be waiting',
    'Thank you!',
    'Can you do it tomorrow?',
    'Please confirm the timing',
  ];

  // Predefined quick reply messages for Providers
  static const List<String> _providerQuickReplies = [
    'Hello! How can I help you?',
    'Yes, I am available',
    'I will be there soon',
    'Please share your address',
    'My charges are reasonable',
    'It will take about 1-2 hours',
    'I am on my way',
    'Work completed successfully!',
    'Thank you for choosing me',
    'Please rate my service',
  ];

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messageSubscription?.unsubscribe();
    super.dispose();
  }

  Future<void> _initializeChat() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      debugPrint('📱 Initializing chat for order: ${widget.orderId}');

      // Get or create chat session
      // The SQL function handles authorization internally
      final response = await SupabaseConfig.supabase.rpc(
        'get_or_create_chat_session',
        params: {'p_order_id': widget.orderId},
      );

      if (response == null || response.isEmpty) {
        throw Exception('Failed to create chat session');
      }

      final session = response.first;
      _sessionId = session['session_id'];

      debugPrint('✅ Chat session ID: $_sessionId');

      // Load existing messages
      await _loadMessages();

      // Setup realtime subscription
      _setupRealtimeSubscription();

      // Mark messages as read
      await _markMessagesAsRead();

      setState(() => _isLoading = false);

      // Scroll to bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    } catch (e) {
      debugPrint('❌ Error initializing chat: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMessages() async {
    try {
      final response = await SupabaseConfig.supabase
          .from('chat_messages')
          .select('*')
          .eq('session_id', _sessionId!)
          .order('created_at', ascending: true);

      setState(() {
        _messages = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      debugPrint('Error loading messages: $e');
    }
  }

  void _setupRealtimeSubscription() {
    _messageSubscription = SupabaseConfig.supabase
        .channel('chat_messages_$_sessionId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'session_id',
            value: _sessionId,
          ),
          callback: (payload) {
            final newMessage = payload.newRecord;
            setState(() {
              _messages.add(newMessage);
            });
            _scrollToBottom();
            _markMessagesAsRead();
          },
        )
        .subscribe();
  }

  Future<void> _markMessagesAsRead() async {
    if (_sessionId == null) return;
    try {
      await SupabaseConfig.supabase.rpc(
        'mark_messages_as_read',
        params: {'p_session_id': _sessionId},
      );
    } catch (e) {
      debugPrint('Error marking messages as read: $e');
    }
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _sessionId == null) return;

    try {
      debugPrint('📤 Sending message to session: $_sessionId');

      // Clear input immediately for better UX
      _messageController.clear();

      // Note: We use custom auth, so Supabase.auth.currentSession might be null.
      // This is expected and handled by passing sender_id explicitly.

      // Send message via RPC
      // We explicitly pass sender_id because the app uses custom auth (not Supabase Auth),
      // so auth.uid() is not available on the server.
      await SupabaseConfig.supabase.rpc(
        'send_chat_message',
        params: {
          'p_session_id': _sessionId,
          'p_order_id': widget.orderId,
          'p_message': message,
          'p_sender_id': widget.userId, // Explicitly pass ID
        },
      );

      debugPrint('✅ Message sent successfully');

      // Message will be added via realtime subscription
      _scrollToBottom();
    } catch (e) {
      debugPrint('❌ Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  void _sendQuickReply(String message) {
    _messageController.text = message;
    _sendMessage();
  }

  List<String> get _quickReplies =>
      widget.isProvider ? _providerQuickReplies : _userQuickReplies;

  Widget _buildQuickReplies() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 50,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            // Quick reply chips
            ..._quickReplies.map(
              (reply) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  onTap: () => _sendQuickReply(reply),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: widget.isProvider
                          ? Colors.green.shade50
                          : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: widget.isProvider
                            ? Colors.green.shade200
                            : Colors.blue.shade200,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      reply,
                      style: TextStyle(
                        fontSize: 13,
                        color: widget.isProvider
                            ? Colors.green.shade700
                            : Colors.blue.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message) {
    // Use widget.userId because we are using custom auth and Supabase auth user is null
    final currentUserId = widget.userId;
    final isSentByMe = message['sender_id'] == currentUserId;
    final messageText = message['message'] ?? '';
    final timestamp = message['created_at'] != null
        ? DateTime.parse(message['created_at'])
        : DateTime.now();

    return Align(
      alignment: isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment: isSentByMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isSentByMe ? Colors.blue.shade500 : Colors.grey.shade300,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isSentByMe ? 16 : 4),
                  bottomRight: Radius.circular(isSentByMe ? 4 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(25),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                messageText,
                style: TextStyle(
                  color: isSentByMe ? Colors.white : Colors.black87,
                  fontSize: 15,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
              child: Text(
                _formatTimestamp(timestamp),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${timestamp.day}/${timestamp.month} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Chat', style: TextStyle(fontSize: 18)),
            Text(
              widget.orderTitle,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red.shade300,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Chat Not Available',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _error!.contains('not available')
                          ? 'Chat is only available for approved orders'
                          : 'Error: $_error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Go Back'),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                // Chat tips banner
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  color: Colors.blue.shade50,
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Colors.blue.shade700,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Chat will be automatically deleted when order is completed or cancelled',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Messages list
                Expanded(
                  child: _messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 64,
                                color: Colors.grey.shade300,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No messages yet',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Start the conversation!',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            return _buildMessageBubble(_messages[index]);
                          },
                        ),
                ),

                // Quick reply chips
                _buildQuickReplies(),

                // Message input
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(25),
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: TextField(
                              controller: _messageController,
                              decoration: InputDecoration(
                                hintText: 'Type a message...',
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade500,
                                ),
                              ),
                              maxLines: null,
                              textCapitalization: TextCapitalization.sentences,
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.blue.shade600,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.send, color: Colors.white),
                            onPressed: _sendMessage,
                            splashRadius: 24,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
