import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Dynamic On-The-Fly Translation Service
/// Auto-detects Windows OS Language and translates strings on-the-fly without JSON files.
class TranslationService {
  static final TranslationService _instance = TranslationService._internal();
  factory TranslationService() => _instance;
  TranslationService._internal();

  /// User selected language code ('auto', 'en', 'es', 'fr', 'de', etc.)
  String _selectedLanguageCode = 'auto';
  String get selectedLanguageCode => _selectedLanguageCode;

  /// Cache for translated strings: Map<"targetLang:sourceText", "translatedText">
  final Map<String, String> _translationCache = {};

  /// Returns the effective target language code ('en', 'es', 'fr', etc.)
  String get effectiveLanguageCode {
    if (_selectedLanguageCode != 'auto') {
      return _selectedLanguageCode.toLowerCase();
    }
    // Auto-detect Windows System Display Language
    final sysLang = PlatformDispatcher.instance.locale.languageCode.toLowerCase();
    return sysLang.isEmpty ? 'en' : sysLang;
  }

  void setLanguage(String langCode) {
    _selectedLanguageCode = langCode;
  }

  /// Translates [text] to the active language code.
  Future<String> translate(String text) async {
    final targetLang = effectiveLanguageCode;

    // If target language is English or text is empty/numbers, no translation needed
    if (targetLang == 'en' || text.trim().isEmpty || _isPureNumberOrSymbol(text)) {
      return text;
    }

    final cacheKey = "$targetLang:$text";
    if (_translationCache.containsKey(cacheKey)) {
      return _translationCache[cacheKey]!;
    }

    try {
      final url = Uri.parse(
        'https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=$targetLang&dt=t&q=${Uri.encodeComponent(text)}',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        if (data.isNotEmpty && data[0] != null && data[0] is List) {
          final StringBuffer sb = StringBuffer();
          for (final item in data[0]) {
            if (item is List && item.isNotEmpty && item[0] != null) {
              sb.write(item[0].toString());
            }
          }
          final result = sb.toString().trim();
          if (result.isNotEmpty) {
            _translationCache[cacheKey] = result;
            return result;
          }
        }
      }
    } catch (_) {
      // Return original text if offline or API timeout occurs
    }

    return text;
  }

  bool _isPureNumberOrSymbol(String text) {
    final clean = text.replaceAll(RegExp(r'[\d\s\-_.:/\\()\[\]{}|@#$%\^&*+=<>?!,]'), '');
    return clean.isEmpty;
  }
}

/// A reactive Text Widget that automatically translates text on-the-fly
class AutoText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final TextOverflow? overflow;
  final int? maxLines;

  const AutoText(
    this.text, {
    Key? key,
    this.style,
    this.textAlign,
    this.overflow,
    this.maxLines,
  }) : super(key: key);

  @override
  State<AutoText> createState() => _AutoTextState();
}

class _AutoTextState extends State<AutoText> {
  late String _displayText;
  bool _isTranslating = false;

  @override
  void initState() {
    super.initState();
    _displayText = widget.text;
    _performTranslation();
  }

  @override
  void didUpdateWidget(covariant AutoText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _displayText = widget.text;
      _performTranslation();
    }
  }

  Future<void> _performTranslation() async {
    final targetLang = TranslationService().effectiveLanguageCode;
    if (targetLang == 'en') return;

    if (mounted) setState(() => _isTranslating = true);
    final translated = await TranslationService().translate(widget.text);
    if (mounted) {
      setState(() {
        _displayText = translated;
        _isTranslating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _displayText,
      style: widget.style,
      textAlign: widget.textAlign,
      overflow: widget.overflow,
      maxLines: widget.maxLines,
    );
  }
}

/// Available languages list for Settings dropdown
class AppLanguageOption {
  final String code;
  final String displayName;
  final String flagEmoji;

  const AppLanguageOption(this.code, this.displayName, this.flagEmoji);

  static const List<AppLanguageOption> options = [
    AppLanguageOption('auto', 'Auto-Detect (Windows OS Default)', '🌐'),
    AppLanguageOption('en', 'English', '🇺🇸'),
    AppLanguageOption('es', 'Spanish (Español)', '🇪🇸'),
    AppLanguageOption('fr', 'French (Français)', '🇫🇷'),
    AppLanguageOption('de', 'German (Deutsch)', '🇩🇪'),
    AppLanguageOption('it', 'Italian (Italiano)', '🇮🇹'),
    AppLanguageOption('pt', 'Portuguese (Português)', '🇵🇹'),
    AppLanguageOption('ru', 'Russian (Русский)', '🇷🇺'),
    AppLanguageOption('ja', 'Japanese (日本語)', '🇯🇵'),
    AppLanguageOption('ko', 'Korean (한국어)', '🇰🇷'),
    AppLanguageOption('zh-cn', 'Chinese Simplified (简体中文)', '🇨🇳'),
    AppLanguageOption('hi', 'Hindi (हिन्दी)', '🇮🇳'),
    AppLanguageOption('ar', 'Arabic (العربية)', '🇸🇦'),
  ];
}
