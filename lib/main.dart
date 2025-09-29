// main.dart
import 'HardCodes.dart'; // optional local file; keep if you already have it
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart'; // for Clipboard
import './HardCodes.dart';
import 'HardCodes.dart' as hardcodes;
void main() {
  runApp(AgriBotApp());
}

class AgriBotApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AgriBot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF2E7D32),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        scaffoldBackgroundColor: const Color(0xFFF7F6F1),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: SplashScreen(),
    );
  }
}

/// Simple splash screen with agriculture icon / tagline
class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  double _opacity = 0.0;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    Timer(const Duration(milliseconds: 200), () {
      setState(() => _opacity = 1.0);
      _controller.forward();
    });
    Timer(const Duration(milliseconds: 1800), () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => AgriBotScreen()),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFFF8E1), Color(0xFFE8F5E9)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 700),
            opacity: _opacity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(
                  Icons.agriculture,
                  size: 110,
                  color: Color(0xFF2E7D32),
                ),
                SizedBox(height: 18),
                Text(
                  'AgriBot',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2E7D32),
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Harvest smarter — local tips for crops, soil & pests',
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFF577A56),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AgriBotScreen extends StatefulWidget {
  @override
  _AgriBotScreenState createState() => _AgriBotScreenState();
}

class _AgriBotScreenState extends State<AgriBotScreen> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final FlutterTts _flutterTts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final ScrollController _scrollController = ScrollController();
  bool _isListening = false;
  String? _userName;
  bool _isThinking = false;


  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    await _ensurePermissions();
    await _loadUserName();
    await _loadMessages();
    // greet user if first time (only if there are no stored messages)
    if (_messages.isEmpty) {
      String greetName = _userName ?? "farmer";
      _addMessage(ChatMessage(
        text:
        "Hello $greetName 🌾 — I'm AgriBot. Ask me about crops, soil, pests, harvesting, or local best practices. Tell me your crop & region for better advice.",
        isUser: false,
      ));
      _speak("Hello $greetName, I'm AgriBot. Tell me your crop and location so I can give better advice.");
      if (_userName == null || _userName!.trim().isEmpty) {
        Future.delayed(const Duration(milliseconds: 700), () => _askForName());
      }
    }
  }

  Future<void> _ensurePermissions() async {
    final micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      await Permission.microphone.request();
    }
  }

  Future<void> _loadUserName() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? name = prefs.getString('agri_user_name');
    if (name != null && name.trim().isNotEmpty) {
      setState(() => _userName = name);
    }
  }

  Future<void> _askForName() async {
    String? typed = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final TextEditingController c = TextEditingController();
        return AlertDialog(
          title: const Text("Welcome to AgriBot"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("What's your name?"),
              const SizedBox(height: 12),
              TextField(
                controller: c,
                autofocus: true,
                decoration: const InputDecoration(hintText: "e.g. Ram, Asha"),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, "Farmer");
              },
              child: const Text("Skip"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, c.text.trim().isEmpty ? "Farmer" : c.text.trim());
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );

    if (typed != null) {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('agri_user_name', typed);
      setState(() {
        _userName = typed;
      });
      _addMessage(ChatMessage(
          text: "Nice to meet you, $_userName! I'll use your name in greetings from now on.",
          isUser: false));
      _speak("Nice to meet you, $_userName.");
    }
  }

  Future<void> _loadMessages() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString('agri_messages');
    if (raw != null) {
      try {
        final List<dynamic> decoded = jsonDecode(raw);
        final loaded = decoded.map((m) => ChatMessage.fromJson(m)).toList();
        setState(() {
          _messages.clear();
          _messages.addAll(loaded);
        });
        // scroll to bottom after short delay so the list renders first
        Future.delayed(const Duration(milliseconds: 200), _scrollToBottom);
      } catch (e) {
        // ignore parse errors and start fresh
        print("Failed to load messages: $e");
      }
    }
  }

  Future<void> _saveMessages() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_messages.map((m) => m.toJson()).toList());
    await prefs.setString('agri_messages', encoded);
  }

  void _addMessage(ChatMessage msg) {
    setState(() {
      _messages.add(msg);
    });
    _saveMessages();
    _scrollToBottom();
  }

  void _insertSystemTyping() {
    setState(() {
      _isThinking = true;
    });
    _scrollToBottom();
  }

  void _removeSystemTyping() {
    setState(() {
      _isThinking = false;
    });
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    Future.delayed(const Duration(milliseconds: 120), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _flutterTts.stop();
    _scrollController.dispose();
    super.dispose();
  }

  /// Sends the user message and retrieves the AI reply.
  void _sendMessage() async {
    String text = _textController.text.trim();
    if (text.isEmpty) return;

    final userMsg = ChatMessage(text: text, isUser: true, createdAt: DateTime.now());
    _addMessage(userMsg);
    _textController.clear();

    // fetch and show bot response
    String? response = await _getBotResponse(text);
    if (response != null && response.trim().isNotEmpty) {
      final bot = ChatMessage(text: response, isUser: false, createdAt: DateTime.now());
      _addMessage(bot);
      _speak(_stripMarkdown(response));
    } else {
      final bot = ChatMessage(
          text: "Sorry, I couldn't get a response right now. Please try again later.",
          isUser: false,
          createdAt: DateTime.now());
      _addMessage(bot);
    }
  }

  /// Calls the Gemini (or other) API to get a response.
  /// Replace your existing _getBotResponse method with this version,
  /// and add the helper `_listAvailableModels()` into the same class.

  /// Replace your existing _getBotResponse with this version.
  /// Also add the _listAvailableModels helper (below) into the same class.

  Future<String?> _getBotResponse(String message) async {
    _insertSystemTyping();

    final String apiUrl =
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent";

    final headers = <String, String>{
      "Content-Type": "application/json",
      "x-goog-api-key": apiKey, // <-- use header like your curl example
    };

    String basePrompt = hardcodes.agriFallbackPrompt;
    String fullPrompt = "$basePrompt\n\nUser: $message\n\nAgriBot:";

    final Map<String, dynamic> payload = {
      "contents": [
        {
          "parts": [
            {"text": fullPrompt}
          ]
        }
      ]
    };

    try {
      final response = await http
          .post(Uri.parse(apiUrl), headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 25));

      _removeSystemTyping();

      // Successful
      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body);

          // Common shapes: look for candidates -> content -> parts -> text
          if (data is Map<String, dynamic>) {
            // 1) candidates path
            if (data.containsKey("candidates")) {
              final cand = data["candidates"];
              if (cand is List && cand.isNotEmpty) {
                try {
                  final text = cand[0]["content"]["parts"][0]["text"];
                  if (text != null) return text.toString();
                } catch (_) {
                  // fallthrough
                }
              }
            }

            // 2) output or choices path (other possible shapes)
            if (data.containsKey("output")) {
              final out = data["output"];
              if (out is String && out.isNotEmpty) return out;
              if (out is Map && out.containsKey("text")) return out["text"].toString();
            }

            // 3) direct attempt: search for any nested 'text' string
            String? found;
            void walk(dynamic node) {
              if (found != null) return;
              if (node is String) return;
              if (node is Map) {
                node.forEach((k, v) {
                  if (found != null) return;
                  if (k == "text" && v is String) {
                    found = v;
                  } else {
                    walk(v);
                  }
                });
              } else if (node is List) {
                for (var it in node) {
                  if (found != null) break;
                  walk(it);
                }
              }
            }

            walk(data);
            if (found != null) return found;
          }

          // If we couldn't parse expected fields, return full body as fallback
          return response.body;
        } catch (e) {
          return "Failed to parse model response: $e";
        }
      }

      // 404 -> try to help by listing models available to the key
      else if (response.statusCode == 404) {
        final List<String> avail = await _listAvailableModels();
        final suggestion = avail.isNotEmpty ? avail.take(6).join(", ") : "(none found)";
        return "Model not found (404). The model name may be unavailable for your API key/project. "
            "Available models (first few): $suggestion. "
            "Please confirm the model name or enable the appropriate API in Cloud Console.";
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        return "Authorization error (${response.statusCode}). Check your API key, billing, and key restrictions in Google Cloud Console.";
      } else {
        // include server body to aid debugging
        return "Error ${response.statusCode}: ${response.reasonPhrase}\n${response.body}";
      }
    } on TimeoutException {
      _removeSystemTyping();
      return "Request timed out. Please check your network and try again.";
    } catch (e) {
      _removeSystemTyping();
      return "Request failed: $e";
    }
  }

  /// Helper: list available models for the API key (uses header `x-goog-api-key`)
  Future<List<String>> _listAvailableModels() async {
    final String listUrl = "https://generativelanguage.googleapis.com/v1beta/models";
    final headers = <String, String>{
      "Content-Type": "application/json",
      "x-goog-api-key": apiKey,
    };

    try {
      final resp = await http.get(Uri.parse(listUrl), headers: headers).timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(resp.body);
        final List models = (body['models'] as List?) ?? [];
        final List<String> names = [];
        for (var m in models) {
          if (m is Map<String, dynamic>) {
            final candidate = m['name'] ?? m['model'] ?? m['displayName'] ?? m['id'];
            if (candidate != null) names.add(candidate.toString());
          } else if (m is String) {
            names.add(m);
          }
        }
        return names;
      } else {
        return ["(unable to list models - status ${resp.statusCode})"];
      }
    } catch (e) {
      return ["(failed to list models: $e)"];
    }
  }



  /// Starts voice recognition (ensures permission first).
  void _startListening() async {
    if (!await Permission.microphone.isGranted) {
      await Permission.microphone.request();
      if (!await Permission.microphone.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Microphone permission denied.")),
        );
        return;
      }
    }

    bool available = await _speech.initialize(
      onStatus: (status) => print("Speech status: $status"),
      onError: (errorNotification) => print("Speech error: $errorNotification"),
    );
    if (available) {
      setState(() => _isListening = true);
      _speech.listen(
        onResult: (result) {
          setState(() {
            _textController.text = result.recognizedWords;
            // keep cursor at end
            _textController.selection = TextSelection.fromPosition(
                TextPosition(offset: _textController.text.length));
          });
          if (result.finalResult) {
            _stopListening();
            _sendMessage();
          }
        },
      );
    } else {
      print("Speech recognition not available.");
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Speech recognition not available.")));
    }
  }

  /// Stops voice recognition.
  void _stopListening() async {
    await _speech.stop();
    setState(() => _isListening = false);
  }

  /// Uses text-to-speech to speak plain text (strip markdown first).
  void _speak(String text) async {
    try {
      await _flutterTts.setLanguage("en-IN");
      await _flutterTts.setPitch(1.0);
      await _flutterTts.speak(text);
    } catch (e) {
      print("TTS error: $e");
    }
  }

  /// Build a chat message widget rendering Markdown.
  Widget _buildMessage(ChatMessage message) {
    final bool isUser = message.isUser;
    final userGradient =
    const LinearGradient(colors: [Color(0xFFFFF8E1), Color(0xFFFFE0B2)]);
    final botGradient =
    const LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)]);

    final bubble = Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        gradient: isUser ? userGradient : botGradient,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(isUser ? 16 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 16),
        ),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(2, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarkdownBody(
            data: message.text,
            selectable: false,
            styleSheet: MarkdownStyleSheet(
              p: TextStyle(
                fontSize: 16,
                color: isUser ? const Color(0xFF3E2F23) : Colors.white,
                fontWeight: FontWeight.w500,
              ),
              strong: TextStyle(
                fontSize: 16,
                color: isUser ? const Color(0xFF3E2F23) : Colors.white,
                fontWeight: FontWeight.w700,
              ),
              em: TextStyle(
                fontSize: 16,
                fontStyle: FontStyle.italic,
                color: isUser ? const Color(0xFF3E2F23) : Colors.white,
              ),
              blockquote:
              TextStyle(color: isUser ? const Color(0xFF3E2F23) : Colors.white70),
              a: TextStyle(
                  decoration: TextDecoration.underline,
                  color: isUser ? const Color(0xFF3E2F23) : Colors.white),
              listBullet: TextStyle(color: isUser ? const Color(0xFF3E2F23) : Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _formatTimestamp(message.createdAt),
            style: TextStyle(
                fontSize: 11,
                color: isUser ? const Color(0xFF7A6A5A) : Colors.white70),
          ),
        ],
      ),
    );

    // GestureDetector wraps to allow long-press copying
    final gestureBubble = GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: _stripMarkdown(message.text)));
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Copied message to clipboard")));
      },
      child: bubble,
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      child: Row(
        mainAxisAlignment:
        isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser)
            Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 3)],
              ),
              child: const Icon(Icons.agriculture, color: Color(0xFF2E7D32), size: 18),
            ),
          Flexible(child: gestureBubble),
          const SizedBox(width: 8),
          if (!isUser)
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF145A32),
                borderRadius: BorderRadius.circular(8),
              ),
              child: IconButton(
                icon: const Icon(Icons.volume_up, color: Colors.white),
                onPressed: () => _speak(_stripMarkdown(message.text)),
                iconSize: 20,
                tooltip: "Listen",
              ),
            ),
          if (isUser)
            Container(
              margin: const EdgeInsets.only(left: 8),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFF2E7D32),
                child: Text(
                  (_userName != null && _userName!.isNotEmpty)
                      ? _userName![0].toUpperCase()
                      : "U",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Remove common markdown syntax for TTS or plain display fallback.
  String _stripMarkdown(String md) {
    String s = md;
    final linkReg = RegExp(r'\[([^\]]+)\]\([^\)]+\)');
    s = s.replaceAllMapped(linkReg, (m) => m.group(1) ?? '');
    s = s.replaceAll(RegExp(r'(```[\s\S]*?```)|(`[^`]*`)'), '');
    s = s.replaceAll(RegExp(r'[*_~#>-]{1,3}'), '');
    s = s.replaceAll(RegExp(r'[\[\]\(\)]'), '');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  String _formatTimestamp(DateTime? t) {
    final dt = t ?? DateTime.now();
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return "$h:$m";
  }

  /// Builds the main UI.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFF7F6F1), Color(0xFFEFF7EE)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Column(
            children: [
              // Top header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)]),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.agriculture, color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "AgriBot",
                          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _userName != null ? "Hello, $_userName 🌾" : "Hello — ask me about your crops",
                          style: TextStyle(color: Colors.white.withOpacity(0.95), fontSize: 12),
                        ),
                      ],
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _askForName,
                      icon: const Icon(Icons.edit, color: Colors.white),
                      tooltip: "Set your name",
                    )
                  ],
                ),
              ),

              // Chat area
              Expanded(
                child: _messages.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.chat_bubble_outline, size: 80, color: Color(0xFF9E9E9E)),
                      SizedBox(height: 12),
                      Text("Start the conversation — ask about crop care, pests, or soil."),
                    ],
                  ),
                )
                    : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(top: 14, bottom: 10),
                  itemCount: _messages.length + (_isThinking ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_isThinking && index == _messages.length) {
                      // typing indicator
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
                        child: Row(
                          children: [
                            Container(
                              margin: const EdgeInsets.only(right: 10),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F5E9),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.agriculture, color: Color(0xFF2E7D32), size: 18),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                              decoration: BoxDecoration(
                                color: Color(0xFF2E7D32),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  SizedBox(
                                      width: 8,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                                  SizedBox(width: 8),
                                  Text("AgriBot is typing...", style: TextStyle(color: Colors.white)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    } else {
                      final message = _messages[index];
                      return _buildMessage(message);
                    }
                  },
                ),
              ),

              // Input area
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F6F2),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    topRight: Radius.circular(14),
                  ),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, -2))],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      iconSize: 30,
                      icon: Icon(
                        _isListening ? CupertinoIcons.mic_fill : CupertinoIcons.mic,
                        color: const Color(0xFF2E7D32),
                      ),
                      onPressed: () {
                        if (!_isListening) {
                          _startListening();
                        } else {
                          _stopListening();
                        }
                      },
                      tooltip: _isListening ? "Stop listening" : "Speak",
                    ),
                    Expanded(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 150),
                        child: TextField(
                          cursorColor: const Color(0xFF2E7D32),
                          cursorWidth: 2.5,
                          controller: _textController,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Color(0xFF2E7D32),
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Roboto',
                          ),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white,
                            hintText: "Ask about crops, soil, pests, weather...",
                            hintStyle: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF6B6B6B),
                              fontWeight: FontWeight.w400,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          minLines: 1,
                          maxLines: 5,
                          keyboardType: TextInputType.multiline,
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF2E7D32),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
                      ),
                      child: IconButton(
                        iconSize: 26,
                        icon: const Icon(Icons.send, color: Colors.white),
                        onPressed: _isThinking ? null : _sendMessage,
                        tooltip: "Send",
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}



/// Model class for a chat message.
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime createdAt;

  ChatMessage({
    required this.text,
    required this.isUser,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'text': text,
    'isUser': isUser,
    'createdAt': createdAt.toIso8601String(),
  };

  static ChatMessage fromJson(dynamic map) {
    final m = map as Map<String, dynamic>;
    DateTime dt;
    try {
      dt = DateTime.parse(m['createdAt'] ?? DateTime.now().toIso8601String());
    } catch (e) {
      dt = DateTime.now();
    }
    return ChatMessage(text: m['text'] ?? '', isUser: m['isUser'] == true, createdAt: dt);
  }
}


// import 'HardCodes.dart';
// import 'package:flutter/cupertino.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_markdown/flutter_markdown.dart';
// import 'dart:convert';
// import 'dart:async';
// import 'package:http/http.dart' as http;
// import 'package:flutter_tts/flutter_tts.dart';
// import 'package:speech_to_text/speech_to_text.dart' as stt;
// import 'package:permission_handler/permission_handler.dart';
// import 'package:shared_preferences/shared_preferences.dart';
//
// void main() {
//   runApp(AgriBotApp());
// }
//
// class AgriBotApp extends StatelessWidget {
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'AgriBot',
//       debugShowCheckedModeBanner: false,
//       theme: ThemeData(
//         // Earthy + lively accent
//         primaryColor: const Color(0xFF2E7D32),
//         colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
//         scaffoldBackgroundColor: const Color(0xFFF7F6F1),
//         fontFamily: 'Roboto',
//       ),
//       home: SplashScreen(),
//     );
//   }
// }
//
// /// Simple splash screen with agriculture icon / tagline
// class SplashScreen extends StatefulWidget {
//   @override
//   _SplashScreenState createState() => _SplashScreenState();
// }
//
// class _SplashScreenState extends State<SplashScreen>
//     with SingleTickerProviderStateMixin {
//   double _opacity = 0.0;
//   late AnimationController _controller;
//
//   @override
//   void initState() {
//     super.initState();
//     _controller =
//         AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
//     // Animate in and then navigate to main screen.
//     Timer(const Duration(milliseconds: 200), () {
//       setState(() => _opacity = 1.0);
//       _controller.forward();
//     });
//     Timer(const Duration(milliseconds: 2000), () {
//       Navigator.of(context).pushReplacement(
//         MaterialPageRoute(builder: (_) => AgriBotScreen()),
//       );
//     });
//   }
//
//   @override
//   void dispose() {
//     _controller.dispose();
//     super.dispose();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       // sunrise gradient
//       body: Container(
//         decoration: const BoxDecoration(
//           gradient: LinearGradient(
//             colors: [Color(0xFFFFF8E1), Color(0xFFE8F5E9)],
//             begin: Alignment.topLeft,
//             end: Alignment.bottomRight,
//           ),
//         ),
//         child: Center(
//           child: AnimatedOpacity(
//             duration: const Duration(milliseconds: 700),
//             opacity: _opacity,
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: const [
//                 Icon(
//                   Icons.agriculture,
//                   size: 110,
//                   color: Color(0xFF2E7D32),
//                 ),
//                 SizedBox(height: 18),
//                 Text(
//                   'AgriBot',
//                   style: TextStyle(
//                     fontSize: 36,
//                     fontWeight: FontWeight.bold,
//                     color: Color(0xFF2E7D32),
//                   ),
//                 ),
//                 SizedBox(height: 8),
//                 Text(
//                   'Harvest smarter — local tips for crops, soil & pests',
//                   style: TextStyle(
//                     fontSize: 16,
//                     color: Color(0xFF577A56),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }
//
// class AgriBotScreen extends StatefulWidget {
//   @override
//   _AgriBotScreenState createState() => _AgriBotScreenState();
// }
//
// class _AgriBotScreenState extends State<AgriBotScreen> {
//   final List<ChatMessage> _messages = [];
//   final TextEditingController _textController = TextEditingController();
//   final FlutterTts _flutterTts = FlutterTts();
//   final stt.SpeechToText _speech = stt.SpeechToText();
//   bool _isListening = false;
//   String? _userName;
//
//   // Use your real key (or HardCodes.dart). I left direct string only for demo — keep your secure storage in prod.
//   static String apiKey = "AIzaSyA2H6dnR4wf8j3Q4fWstqkS2LHOgay0UOM" ;
//
//   /// Farmer-specific fallback prompt (used when hardcodes.BasePrompt is empty)
//   final String _agriFallbackPrompt = '''
// You are AgriBot — a friendly, practical assistant for farmers. Provide concise, actionable, and safe agricultural advice tailored for smallholder farmers. When asked about:
// - **crops:** give planting times, spacing, watering, common pests and low-risk control measures, nutrient suggestions (use simple fertilizers like NPK or organic alternatives).
// - **soil:** explain basic soil tests, simple improvements (compost, green manure), and watering tips.
// - **pests and diseases:** describe common symptoms, non-harmful home remedies when appropriate, and recommend contacting local agricultural extension services for pesticide/chemical use — do not provide step-by-step hazardous chemical application instructions.
// - **weather, storage, and harvesting:** give best-practice tips, indicators for harvest readiness, and safe storage advice.
// Always ask follow-up questions to clarify crop type, location (region/climate), and growth stage. Use simple language, local-friendly examples, and suggest local resources (extension offices, trusted agronomy helplines) when appropriate.
// If you are unsure about a hazardous or medical issue, advise seeking professional/local expert help.
// ''';
//
//   @override
//   void initState() {
//     super.initState();
//     _initApp();
//   }
//
//   Future<void> _initApp() async {
//     await _ensurePermissions();
//     await _loadUserName();
//     // greet user on open
//     String greetName = _userName ?? "farmer";
//     setState(() {
//       _messages.add(ChatMessage(
//           text:
//           "Hello $greetName 🌾 — I'm AgriBot. Ask me about crops, soil, pests, harvesting, or local best practices. Tell me your crop & region for better advice.",
//           isUser: false));
//     });
//     _speak("Hello $greetName, I'm AgriBot. Tell me your crop and location so I can give better advice.");
//     // Also prompt for name if not present
//     if (_userName == null || _userName!.trim().isEmpty) {
//       Future.delayed(const Duration(milliseconds: 700), () => _askForName());
//     }
//   }
//
//   Future<void> _ensurePermissions() async {
//     // request microphone permission for speech_to_text
//     final micStatus = await Permission.microphone.status;
//     if (!micStatus.isGranted) {
//       await Permission.microphone.request();
//     }
//     // Optionally request storage if you plan to use files
//     // final storageStatus = await Permission.storage.status;
//     // if (!storageStatus.isGranted) await Permission.storage.request();
//   }
//
//   Future<void> _loadUserName() async {
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//     String? name = prefs.getString('agri_user_name');
//     if (name != null && name.trim().isNotEmpty) {
//       setState(() => _userName = name);
//     }
//   }
//
//   Future<void> _askForName() async {
//     String? typed = await showDialog<String>(
//       context: context,
//       barrierDismissible: false,
//       builder: (context) {
//         final TextEditingController c = TextEditingController();
//         return AlertDialog(
//           title: const Text("Welcome to AgriBot"),
//           content: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               const Text("What's your name?"),
//               const SizedBox(height: 12),
//               TextField(
//                 controller: c,
//                 autofocus: true,
//                 decoration: const InputDecoration(hintText: "e.g. Ram, Asha"),
//               ),
//             ],
//           ),
//           actions: [
//             TextButton(
//               onPressed: () {
//                 Navigator.pop(context, "Farmer");
//               },
//               child: const Text("Skip"),
//             ),
//             ElevatedButton(
//               onPressed: () {
//                 Navigator.pop(context, c.text.trim().isEmpty ? "Farmer" : c.text.trim());
//               },
//               child: const Text("Save"),
//             ),
//           ],
//         );
//       },
//     );
//
//     if (typed != null) {
//       SharedPreferences prefs = await SharedPreferences.getInstance();
//       await prefs.setString('agri_user_name', typed);
//       setState(() {
//         _userName = typed;
//         // Update greeting message (prepend a small bot message)
//         _messages.insert(
//             0,
//             ChatMessage(
//                 text:
//                 "Nice to meet you, $_userName! I'll use your name in greetings from now on.",
//                 isUser: false));
//       });
//       _speak("Nice to meet you, $_userName.");
//     }
//   }
//
//   @override
//   void dispose() {
//     _textController.dispose();
//     _flutterTts.stop();
//     super.dispose();
//   }
//
//   /// Sends the user message and retrieves the AI reply.
//   void _sendMessage() async {
//     String text = _textController.text.trim();
//     if (text.isEmpty) return;
//
//     setState(() {
//       _messages.add(ChatMessage(text: text, isUser: true));
//     });
//     _textController.clear();
//
//     String? response = await _getBotResponse(text);
//     if (response != null) {
//       setState(() {
//         _messages.add(ChatMessage(text: response, isUser: false));
//       });
//       _speak(_stripMarkdown(response));
//     }
//   }
//
//   /// Calls the Gemini API to get a response.
//   Future<String?> _getBotResponse(String message) async {
//     String apiUrl =
//         "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$apiKey";
//
//     // prefer user-supplied BasePrompt; fallback to _agriFallbackPrompt
//     String basePrompt =  _agriFallbackPrompt;
//
//     // Compose a farmer-friendly conversation prompt
//     String fullPrompt = "$basePrompt\n\nUser: $message\n\nAgriBot:";
//
//     try {
//       final response = await http.post(
//         Uri.parse(apiUrl),
//         headers: {"Content-Type": "application/json"},
//         body: jsonEncode({
//           "contents": [
//             {
//               "parts": [
//                 {"text": fullPrompt}
//               ]
//             }
//           ]
//         }),
//       );
//
//       if (response.statusCode == 200) {
//         final data = jsonDecode(response.body);
//         if (data["candidates"] != null && data["candidates"].isNotEmpty) {
//           return data["candidates"][0]["content"]["parts"][0]["text"];
//         } else {
//           return "No response from the API.";
//         }
//       } else {
//         return "Error: ${response.statusCode}";
//       }
//     } catch (e) {
//       return "Error: $e";
//     }
//   }
//
//   /// Starts voice recognition (ensures permission first).
//   void _startListening() async {
//     // request mic permission at the moment of use as well
//     if (!await Permission.microphone.isGranted) {
//       await Permission.microphone.request();
//       if (!await Permission.microphone.isGranted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(content: Text("Microphone permission denied.")),
//         );
//         return;
//       }
//     }
//
//     bool available = await _speech.initialize(
//       onStatus: (status) => print("Speech status: $status"),
//       onError: (errorNotification) => print("Speech error: $errorNotification"),
//     );
//     if (available) {
//       setState(() => _isListening = true);
//       _speech.listen(
//         onResult: (result) {
//           setState(() {
//             _textController.text = result.recognizedWords;
//           });
//           if (result.finalResult) {
//             _stopListening();
//             _sendMessage();
//           }
//         },
//       );
//     } else {
//       print("Speech recognition not available.");
//     }
//   }
//
//   /// Stops voice recognition.
//   void _stopListening() async {
//     await _speech.stop();
//     setState(() => _isListening = false);
//   }
//
//   /// Uses text-to-speech to speak plain text (strip markdown first).
//   void _speak(String text) async {
//     await _flutterTts.setLanguage("en-IN"); // slightly more local accent
//     await _flutterTts.setPitch(1.0);
//     await _flutterTts.speak(text);
//   }
//
//   /// Build a chat message widget rendering Markdown.
//   Widget _buildMessage(ChatMessage message) {
//     bool isUser = message.isUser;
//
//     // bubble gradient colors
//     final userGradient = const LinearGradient(colors: [Color(0xFFFFF8E1), Color(0xFFFFE0B2)]);
//     final botGradient = const LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)]);
//
//     return Container(
//       margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
//       alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
//       child: Row(
//         mainAxisSize: MainAxisSize.min,
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           if (!isUser)
//             Container(
//               margin: const EdgeInsets.only(right: 8),
//               padding: const EdgeInsets.all(8),
//               decoration: BoxDecoration(
//                 color: const Color(0xFFE8F5E9),
//                 shape: BoxShape.circle,
//                 boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 3)],
//               ),
//               child: const Icon(Icons.agriculture, color: Color(0xFF2E7D32), size: 18),
//             ),
//           Flexible(
//             child: ConstrainedBox(
//               constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
//               child: Container(
//                 padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
//                 decoration: BoxDecoration(
//                   gradient: isUser ? userGradient : botGradient,
//                   borderRadius: BorderRadius.circular(16),
//                   boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(2,2))],
//                 ),
//                 child: MarkdownBody(
//                   data: message.text,
//                   selectable: false,
//                   styleSheet: MarkdownStyleSheet(
//                     p: TextStyle(
//                       fontSize: 16,
//                       color: isUser ? const Color(0xFF3E2F23) : Colors.white,
//                       fontWeight: FontWeight.w500,
//                     ),
//                     strong: TextStyle(
//                       fontSize: 16,
//                       color: isUser ? const Color(0xFF3E2F23) : Colors.white,
//                       fontWeight: FontWeight.w700,
//                     ),
//                     em: TextStyle(
//                       fontSize: 16,
//                       fontStyle: FontStyle.italic,
//                       color: isUser ? const Color(0xFF3E2F23) : Colors.white,
//                     ),
//                     blockquote: TextStyle(color: isUser ? const Color(0xFF3E2F23) : Colors.white70),
//                     a: TextStyle(decoration: TextDecoration.underline, color: isUser ? const Color(0xFF3E2F23) : Colors.white),
//                     listBullet: TextStyle(color: isUser ? const Color(0xFF3E2F23) : Colors.white),
//                   ),
//                 ),
//               ),
//             ),
//           ),
//           if (!isUser)
//             Padding(
//               padding: const EdgeInsets.only(left: 8),
//               child: Container(
//                 padding: const EdgeInsets.all(6),
//                 decoration: BoxDecoration(
//                   color: const Color(0xFF145A32),
//                   borderRadius: BorderRadius.circular(8),
//                 ),
//                 child: IconButton(
//                   icon: const Icon(Icons.volume_up, color: Colors.white),
//                   onPressed: () => _speak(_stripMarkdown(message.text)),
//                   iconSize: 22,
//                 ),
//               ),
//             ),
//         ],
//       ),
//     );
//   }
//
//   /// Remove common markdown syntax for TTS or plain display fallback.
//   String _stripMarkdown(String md) {
//     String s = md;
//     // Convert markdown links [text](url) -> text
//     final linkReg = RegExp(r'\[([^\]]+)\]\([^\)]+\)');
//     s = s.replaceAllMapped(linkReg, (m) => m.group(1) ?? '');
//
//     // Remove emphasis markers and code ticks, headings, separators etc.
//     s = s.replaceAll(RegExp(r'(```[\s\S]*?```)|(`[^`]*`)'), ''); // remove code blocks / inline code
//     s = s.replaceAll(RegExp(r'[*_~#>-]{1,3}'), '');
//     // remove remaining square/round braces
//     s = s.replaceAll(RegExp(r'[\[\]\(\)]'), '');
//     // collapse multiple spaces/newlines
//     s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
//     return s;
//   }
//
//   /// Builds the main UI.
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       // subtle background gradient
//       body: SafeArea(
//         child: Container(
//           decoration: const BoxDecoration(
//             gradient: LinearGradient(
//               colors: [Color(0xFFF7F6F1), Color(0xFFEFF7EE)],
//               begin: Alignment.topCenter,
//               end: Alignment.bottomCenter,
//             ),
//           ),
//           child: Column(
//             children: [
//               // Top App Bar replacement with a custom header
//               Container(
//                 padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//                 decoration: const BoxDecoration(
//                   gradient: LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)]),
//                   borderRadius: BorderRadius.only(
//                     bottomLeft: Radius.circular(18),
//                     bottomRight: Radius.circular(18),
//                   ),
//                 ),
//                 child: Row(
//                   children: [
//                     const Icon(Icons.agriculture, color: Colors.white, size: 28),
//                     const SizedBox(width: 12),
//                     Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Text(
//                           "AgriBot",
//                           style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
//                         ),
//                         Text(
//                           _userName != null ? "Hello, $_userName 🌾" : "Hello — ask me about your crops",
//                           style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12),
//                         ),
//                       ],
//                     ),
//                     const Spacer(),
//                     IconButton(
//                       onPressed: _askForName,
//                       icon: const Icon(Icons.edit, color: Colors.white),
//                       tooltip: "Set your name",
//                     )
//                   ],
//                 ),
//               ),
//
//               // Chat area
//               Expanded(
//                 child: ListView.builder(
//                   padding: const EdgeInsets.only(top: 14, bottom: 10),
//                   itemCount: _messages.length,
//                   itemBuilder: (context, index) => _buildMessage(_messages[index]),
//                 ),
//               ),
//
//               // Input area
//               Container(
//                 padding: const EdgeInsets.all(10),
//                 decoration: BoxDecoration(
//                   color: const Color(0xFFF1F6F2),
//                   borderRadius: const BorderRadius.only(
//                     topLeft: Radius.circular(14),
//                     topRight: Radius.circular(14),
//                   ),
//                   boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0,-2))],
//                 ),
//                 child: Row(
//                   crossAxisAlignment: CrossAxisAlignment.end,
//                   children: [
//                     IconButton(
//                       iconSize: 30,
//                       icon: Icon(
//                         _isListening ? CupertinoIcons.mic_fill : CupertinoIcons.mic,
//                         color: const Color(0xFF2E7D32),
//                       ),
//                       onPressed: () {
//                         if (!_isListening) {
//                           _startListening();
//                         } else {
//                           _stopListening();
//                         }
//                       },
//                     ),
//                     Expanded(
//                       child: ConstrainedBox(
//                         constraints: const BoxConstraints(maxHeight: 150),
//                         child: SingleChildScrollView(
//                           child: TextField(
//                             cursorColor: const Color(0xFF2E7D32),
//                             cursorWidth: 2.5,
//                             controller: _textController,
//                             style: const TextStyle(
//                               fontSize: 16,
//                               color: Color(0xFF2E7D32),
//                               fontWeight: FontWeight.w500,
//                               fontFamily: 'Roboto',
//                             ),
//                             decoration: const InputDecoration(
//                               hintText: "Ask about crops, soil, pests, weather...",
//                               hintStyle: TextStyle(
//                                 fontSize: 14,
//                                 color: Color(0xFF6B6B6B),
//                                 fontWeight: FontWeight.w400,
//                               ),
//                               border: InputBorder.none,
//                               contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//                             ),
//                             minLines: 1,
//                             maxLines: 5,
//                             keyboardType: TextInputType.multiline,
//                           ),
//                         ),
//                       ),
//                     ),
//                     IconButton(
//                       iconSize: 30,
//                       icon: const Icon(Icons.send, color: Color(0xFF2E7D32)),
//                       onPressed: _sendMessage,
//                     ),
//                   ],
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }
//
// /// Model class for a chat message.
// class ChatMessage {
//   final String text;
//   final bool isUser;
//
//   ChatMessage({required this.text, required this.isUser});
// }
