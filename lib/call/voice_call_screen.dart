import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:mrhelper/call/livekit_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

/// Voice Call Screen - Modern UI for LiveKit voice calls
class VoiceCallScreen extends StatefulWidget {
  final String orderId;
  final String callerName;
  final String calleeName;
  final bool isCaller;
  final String? calleeId;

  const VoiceCallScreen({
    super.key,
    required this.orderId,
    required this.callerName,
    required this.calleeName,
    required this.isCaller,
    this.calleeId,
  });

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen>
    with SingleTickerProviderStateMixin {
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  Timer? _callTimer;
  int _callDurationSeconds = 0;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  CallStatus _callStatus = CallStatus.connecting;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 1.0, curve: Curves.easeOut),
      ),
    );
    _animationController.forward();
    _requestMicrophonePermission();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _callTimer?.cancel();
    _listener?.dispose();
    _disconnectRoom();
    super.dispose();
  }

  /// Request microphone permission
  Future<void> _requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) {
      debugPrint('Microphone permission granted');
      _startCall();
    } else {
      debugPrint('Microphone permission denied');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission required for voice calls'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  /// Start the voice call
  Future<void> _startCall() async {
    setState(() {
      _callStatus = CallStatus.connecting;
    });

    final token = await LiveKitService().fetchToken(
      roomName: widget.orderId,
      userName: widget.callerName,
    );

    if (token == null) {
      setState(() {
        _callStatus = CallStatus.failed;
        _errorMessage = 'Failed to connect to call server';
      });
      await Future.delayed(const Duration(seconds: 2));
      Navigator.pop(context);
      return;
    }

    _room = await LiveKitService().connectRoom(
      token: token,
      roomName: widget.orderId,
      onConnected: (room) {
        debugPrint('Local peer connected successfully');
        _setupRoomListeners(room);
      },
      onDisconnected: (room) {
        debugPrint('Call disconnected');
        _endCallInternal();
      },
      onError: (error) {
        debugPrint('Call error: $error');
        if (mounted) {
          setState(() {
            _callStatus = CallStatus.failed;
            _errorMessage = error;
          });
        }
      },
    );
  }

  void _setupRoomListeners(Room room) {
    _listener = room.createListener();

    // Check if there are already remote participants (in case we are the callee)
    if (room.remoteParticipants.isNotEmpty) {
      _startTimerAndConnect();
    }

    _listener?.on<ParticipantConnectedEvent>((event) {
      debugPrint('Participant connected: ${event.participant.identity}');
      _startTimerAndConnect();
    });

    _listener?.on<ParticipantDisconnectedEvent>((event) {
      debugPrint('Participant disconnected: ${event.participant.identity}');
      // If the other person leaves, end the call
      if (room.remoteParticipants.isEmpty) {
        _endCallInternal();
      }
    });
  }

  void _startTimerAndConnect() {
    if (_callStatus == CallStatus.connected) return; // Already connected
    if (!mounted) return;

    setState(() {
      _callStatus = CallStatus.connected;
      _callDurationSeconds = 0;
    });

    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _callDurationSeconds++;
        });
      }
    });
  }

  void _endCallInternal() {
    _callTimer?.cancel();
    
    // If caller hangs up before connected, cancel the call on callee side
    if (widget.isCaller && _callStatus == CallStatus.ringing && widget.calleeId != null) {
      CallSignalingService.instance.sendCancellation(
        calleeId: widget.calleeId!,
        orderId: widget.orderId,
      );
    }
    
    if (mounted) {
      setState(() {
        _callStatus = CallStatus.ended;
      });
      // Optionally delay popping so they see "Call Ended"
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  /// Disconnect from the room
  Future<void> _disconnectRoom() async {
    _callTimer?.cancel();
    _listener?.dispose();
    if (_room != null) {
      await _room?.disconnect();
      _room = null;
    }
  }

  /// Toggle microphone mute
  Future<void> _toggleMute() async {
    if (_room == null) return;

    setState(() {
      _isMuted = !_isMuted;
    });

    // Use setMicrophoneEnabled (livekit_client v2 API)
    await _room?.localParticipant?.setMicrophoneEnabled(!_isMuted);
  }

  /// Toggle speakerphone
  Future<void> _toggleSpeaker() async {
    if (_room == null) return;

    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
    });

    // TODO: Implement speakerphone toggle using platform channels
    // This requires native iOS/Android implementation
    debugPrint('Speaker toggle: $_isSpeakerOn');
  }

  /// End the call
  Future<void> _endCall() async {
    _endCallInternal();
    await _disconnectRoom();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 20),
              child: Text(
                'Voice Call',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
            ),

            // Caller/Callee Info
            Expanded(
              flex: 2,
              child: Center(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Avatar placeholder
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade800,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          Icons.person,
                          size: 50,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Name
                      Text(
                        widget.calleeName,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      // Status
                      const SizedBox(height: 8),
                      Text(
                        _getStatusText(),
                        style: TextStyle(
                          fontSize: 18,
                          color: _getStatusColor(),
                        ),
                      ),
                      if (_errorMessage.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.red[400],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // Controls
            Expanded(
              flex: 2,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildControlButton(
                    icon: _isMuted ? Icons.mic_off : Icons.mic,
                    label: _isMuted ? 'Unmute' : 'Mute',
                    onPressed: _toggleMute,
                  ),
                  const SizedBox(height: 32),
                  _buildControlButton(
                    icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                    label: _isSpeakerOn ? 'Headset' : 'Speaker',
                    onPressed: _toggleSpeaker,
                  ),
                ],
              ),
            ),

            // End Call Button
            Padding(
              padding: const EdgeInsets.all(40),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: ElevatedButton(
                  onPressed: _endCall,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 20,
                    ),
                    shape: const CircleBorder(),
                    minimumSize: const Size(80, 80),
                    elevation: 0,
                  ),
                  child: const Icon(
                    Icons.call_end,
                    size: 40,
                  ),
                ),
              ),
            ),

            // Bottom spacing
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  /// Get status text based on call status
  String _getStatusText() {
    switch (_callStatus) {
      case CallStatus.connecting:
        return widget.isCaller ? 'Ringing...' : 'Connecting...';
      case CallStatus.connected:
        return _formatDuration(_callDurationSeconds);
      case CallStatus.ended:
        return 'Call Ended';
      case CallStatus.failed:
        return 'Failed';
    }
  }

  /// Get status color based on call status
  Color _getStatusColor() {
    switch (_callStatus) {
      case CallStatus.connecting:
        return Colors.orange[400]!;
      case CallStatus.connected:
        return Colors.green[400]!;
      case CallStatus.ended:
        return Colors.grey[600]!;
      case CallStatus.failed:
        return Colors.red[400]!;
    }
  }

  /// Build control button (mute, speaker)
  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 32,
              color: Colors.white,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Voice call status
enum CallStatus {
  connecting,
  connected,
  ended,
  failed,
}