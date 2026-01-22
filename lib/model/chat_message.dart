class ChatMessage {
  final String sender;
  final String content;
  final DateTime timestamp;
  final bool isMe;

  ChatMessage({
    required this.sender,
    required this.content,
    required this.timestamp,
    required this.isMe,
  });

  factory ChatMessage.fromMap(Map<dynamic, dynamic> map, {bool isMe = false}) {
    return ChatMessage(
      sender: map['sender'] ?? 'Unknown',
      content: map['content'] ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] ?? DateTime.now().millisecondsSinceEpoch),
      isMe: isMe,
    );
  }
}
