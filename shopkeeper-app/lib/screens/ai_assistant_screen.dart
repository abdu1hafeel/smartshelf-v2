// ==============================================================================
// SmartShelf V2 - AI Shopkeeper Assistant Screen
// ==============================================================================

import 'package:flutter/material.dart';
import '../models/ai_message.dart';
import '../models/shop.dart';
import '../services/ai_assistant_service.dart';
import '../services/auth_service.dart';
import 'inventory_screen.dart';
import 'sales_history_screen.dart';

class AiAssistantScreen extends StatefulWidget {
  final Shop shop;
  final AuthService? authService;

  const AiAssistantScreen({
    super.key,
    required this.shop,
    this.authService,
  });

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final AiAssistantService _assistantService = AiAssistantService();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  final List<AiMessage> _messages = [];
  bool _isThinking = false;
  String? _lastFailedQuestion;

  static const List<String> _suggestedPrompts = [
    'How much revenue did my shop generate today?',
    'Which items are running low on stock?',
    'What should I restock today?',
    'How is this month performing compared to last month?',
    'What are my top-selling products this week?',
    'Which products have had no sales in the last 14 days?',
  ];

  @override
  void initState() {
    super.initState();
    _addInitialGreeting();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _addInitialGreeting() {
    _messages.add(
      AiMessage(
        id: 'welcome-${DateTime.now().millisecondsSinceEpoch}',
        text: '👋 Hello! I am your **SmartShelf AI Assistant**.\n\n'
            'I have real-time access to inventory, sales metrics, and restock analytics for **${widget.shop.name}**.\n\n'
            'Ask me anything about today’s revenue, low stock alerts, restock orders, or tap one of the suggested questions below.',
        isUser: false,
        timestamp: DateTime.now(),
        intent: 'GREETING',
      ),
    );
  }

  void _clearChat() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Conversation?'),
        content: const Text('This will reset the assistant chat history for this session.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _messages.clear();
                _lastFailedQuestion = null;
                _addInitialGreeting();
              });
            },
            child: const Text('Clear', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSubmitted(String text) async {
    final query = text.trim();
    if (query.isEmpty || _isThinking) return;

    _textController.clear();
    _focusNode.unfocus();

    final userMsg = AiMessage(
      id: 'usr-${DateTime.now().millisecondsSinceEpoch}',
      text: query,
      isUser: true,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMsg);
      _isThinking = true;
      _lastFailedQuestion = null;
    });

    _scrollToBottom();

    try {
      final response = await _assistantService.askAssistant(
        shopId: widget.shop.id,
        question: query,
      );

      if (!mounted) return;

      setState(() {
        _isThinking = false;
        _messages.add(response);
        if (response.isError) {
          _lastFailedQuestion = query;
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isThinking = false;
        _lastFailedQuestion = query;
        _messages.add(
          AiMessage(
            id: 'err-${DateTime.now().millisecondsSinceEpoch}',
            text: '⚠️ Unable to complete request: $e\n\nPlease check your local network connection and try again.',
            isUser: false,
            timestamp: DateTime.now(),
            isError: true,
          ),
        );
      });
    }

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0.5,
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Text(
                        'AI Shopkeeper Assistant',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${widget.shop.name} • Live Store AI',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, color: Color(0xFF64748B)),
            tooltip: 'Clear Chat',
            onPressed: _messages.length > 1 ? _clearChat : null,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Quick Suggestion Chips Bar
            _buildSuggestedChipsBar(),

            // Chat Messages List
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                itemCount: _messages.length + (_isThinking ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _messages.length && _isThinking) {
                    return _buildThinkingBubble();
                  }
                  final msg = _messages[index];
                  return _buildMessageBubble(msg);
                },
              ),
            ),

            // Retry Banner if error occurred
            if (_lastFailedQuestion != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                color: const Color(0xFFFEF2F2),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Last request failed. Tap retry to resend.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF991B1B)),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                        final retryQ = _lastFailedQuestion;
                        if (retryQ != null) {
                          _handleSubmitted(retryQ);
                        }
                      },
                      child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFEF4444))),
                    ),
                  ],
                ),
              ),

            // Input Bar
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Suggested Chips Bar
  // ---------------------------------------------------------------------------
  Widget _buildSuggestedChipsBar() {
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: _suggestedPrompts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final prompt = _suggestedPrompts[index];
          return ActionChip(
            visualDensity: VisualDensity.compact,
            backgroundColor: const Color(0xFFF1F5F9),
            side: BorderSide(color: Colors.indigo.shade100),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
            avatar: const Icon(
              Icons.auto_awesome,
              size: 13,
              color: Color(0xFF4F46E5),
            ),
            label: Text(
              prompt,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1E293B),
              ),
            ),
            onPressed: _isThinking ? null : () => _handleSubmitted(prompt),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Message Bubbles
  // ---------------------------------------------------------------------------
  Widget _buildMessageBubble(AiMessage msg) {
    if (msg.isUser) {
      return _buildUserBubble(msg);
    } else {
      return _buildAssistantBubble(msg);
    }
  }

  Widget _buildUserBubble(AiMessage msg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 48),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4F46E5), Color(0xFF4338CA)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4F46E5).withValues(alpha: 0.18),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    msg.text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(msg.timestamp),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 14,
            backgroundColor: const Color(0xFFE0E7FF),
            child: const Icon(Icons.person_rounded, size: 16, color: Color(0xFF4338CA)),
          ),
        ],
      ),
    );
  }

  Widget _buildAssistantBubble(AiMessage msg) {
    final isError = msg.isError;
    final hasFollowUp = msg.intent != null && !isError;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14, right: 32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: isError
                  ? const LinearGradient(colors: [Color(0xFFEF4444), Color(0xFFDC2626)])
                  : const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isError ? Icons.error_outline_rounded : Icons.auto_awesome,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isError ? const Color(0xFFFEF2F2) : Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                border: Border.all(
                  color: isError ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Verification badge
                  if (!isError && msg.intent != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified_rounded, size: 12, color: Color(0xFF059669)),
                          SizedBox(width: 4),
                          Text(
                            'Verified from SmartShelf Live Database',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF065F46),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Message body
                  SelectableText(
                    msg.text,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      color: isError ? const Color(0xFF991B1B) : const Color(0xFF1E293B),
                    ),
                  ),

                  // Structured Table / Cards if Raw Data Available
                  if (msg.rawData != null) _buildStructuredDataView(msg),

                  // Quick Action Follow-ups
                  if (hasFollowUp) _buildFollowUpActions(msg.intent!),

                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        _formatTime(msg.timestamp),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Structured Data Cards & Tables
  // ---------------------------------------------------------------------------
  Widget _buildStructuredDataView(AiMessage msg) {
    final data = msg.rawData!;
    final intent = msg.intent;

    if (intent == 'LOW_STOCK' && data['low_stock_items'] is List) {
      final items = data['low_stock_items'] as List;
      if (items.isEmpty) return const SizedBox.shrink();

      return Container(
        margin: const EdgeInsets.only(top: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFD97706)),
                  SizedBox(width: 4),
                  Text(
                    'LOW STOCK INVENTORY TABLE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: Color(0xFF92400E),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFFDE68A)),
            ...items.take(5).map((it) {
              final name = it['product_name'] ?? 'Item';
              final current = it['current_stock'] ?? 0;
              final threshold = it['low_stock_threshold'] ?? 0;
              final unit = it['unit_type'] == 'kg' ? 'kg' : 'pcs';
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '$current / $threshold $unit',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      );
    }

    if (intent == 'RESTOCK' && data['restock_recommendations'] is List) {
      final recs = data['restock_recommendations'] as List;
      if (recs.isEmpty) return const SizedBox.shrink();

      return Container(
        margin: const EdgeInsets.only(top: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFBBF7D0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: Row(
                children: [
                  Icon(Icons.local_shipping_outlined, size: 14, color: Color(0xFF16A34A)),
                  SizedBox(width: 4),
                  Text(
                    'RECOMMENDED PURCHASE ORDERS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: Color(0xFF166534),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFBBF7D0)),
            ...recs.take(5).map((r) {
              final name = r['product_name'] ?? 'Item';
              final qty = r['recommended_order_quantity'] ?? 0;
              final urgency = r['urgency'] ?? 'NORMAL';
              final unit = r['unit_type'] == 'kg' ? 'kg' : 'pcs';

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: urgency == 'HIGH' ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '+$qty $unit ($urgency)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: urgency == 'HIGH' ? const Color(0xFF991B1B) : const Color(0xFF166534),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  // ---------------------------------------------------------------------------
  // Contextual Follow-Up Buttons
  // ---------------------------------------------------------------------------
  Widget _buildFollowUpActions(String intent) {
    List<Widget> actions = [];

    if (intent == 'TODAY_SALES' || intent == 'MONTH_SALES' || intent == 'TOP_SELLING') {
      actions.add(
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            side: const BorderSide(color: Color(0xFF6366F1)),
            foregroundColor: const Color(0xFF4F46E5),
          ),
          icon: const Icon(Icons.receipt_long_rounded, size: 14),
          label: const Text('View Sales History', style: TextStyle(fontSize: 12)),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SalesHistoryScreen(shop: widget.shop),
              ),
            );
          },
        ),
      );
    }

    if (intent == 'LOW_STOCK' || intent == 'RESTOCK' || intent == 'SLOW_MOVING') {
      actions.add(
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            side: const BorderSide(color: Color(0xFF10B981)),
            foregroundColor: const Color(0xFF059669),
          ),
          icon: const Icon(Icons.inventory_2_outlined, size: 14),
          label: const Text('Open Store Inventory', style: TextStyle(fontSize: 12)),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => InventoryScreen(shop: widget.shop),
              ),
            );
          },
        ),
      );
    }

    if (actions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: actions,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Thinking / Typing Bubble
  // ---------------------------------------------------------------------------
  Widget _buildThinkingBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, right: 60),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  'Querying store metrics & analyzing...',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Input Bar
  // ---------------------------------------------------------------------------
  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                textInputAction: TextInputAction.send,
                onSubmitted: _handleSubmitted,
                enabled: !_isThinking,
                decoration: const InputDecoration(
                  hintText: 'Ask about sales, stock, restock...',
                  hintStyle: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF4F46E5), Color(0xFF4338CA)],
              ),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: _isThinking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
              onPressed: _isThinking
                  ? null
                  : () {
                      _handleSubmitted(_textController.text);
                    },
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}
