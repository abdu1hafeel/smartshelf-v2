// ==============================================================================
// SmartShelf V2 - AI Assistant Chat Message Model
// ==============================================================================

class AiMessage {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final String? intent;
  final Map<String, dynamic>? metrics;
  final bool isError;
  final bool isVerified;

  const AiMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.intent,
    this.metrics,
    Map<String, dynamic>? rawData,
    this.isError = false,
    this.isVerified = true,
  }) : rawDataOverride = rawData;

  final Map<String, dynamic>? rawDataOverride;

  Map<String, dynamic>? get rawData => metrics ?? rawDataOverride;

  factory AiMessage.user(String text) {
    return AiMessage(
      id: 'usr_${DateTime.now().microsecondsSinceEpoch}',
      text: text.trim(),
      isUser: true,
      timestamp: DateTime.now(),
    );
  }

  factory AiMessage.assistant({
    required String text,
    String? intent,
    Map<String, dynamic>? metrics,
    Map<String, dynamic>? rawData,
  }) {
    return AiMessage(
      id: 'ast_${DateTime.now().microsecondsSinceEpoch}',
      text: text.trim(),
      isUser: false,
      timestamp: DateTime.now(),
      intent: intent,
      metrics: metrics ?? rawData,
      isVerified: true,
    );
  }

  factory AiMessage.error(String errorMessage) {
    return AiMessage(
      id: 'err_${DateTime.now().microsecondsSinceEpoch}',
      text: errorMessage,
      isUser: false,
      timestamp: DateTime.now(),
      isError: true,
      isVerified: false,
    );
  }
}
