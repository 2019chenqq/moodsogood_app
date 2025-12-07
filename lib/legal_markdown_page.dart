import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown/flutter_markdown.dart';

class LegalMarkdownPage extends StatefulWidget {
  final String title;
  final String assetPath;
  const LegalMarkdownPage({super.key, required this.title, required this.assetPath});

  @override
  State<LegalMarkdownPage> createState() => _LegalMarkdownPageState();
}

class _LegalMarkdownPageState extends State<LegalMarkdownPage> {
  String? _md;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final text = await rootBundle.loadString(widget.assetPath);
    if (mounted) setState(() => _md = text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _md == null
          ? const Center(child: CircularProgressIndicator())
          : Markdown(
              data: _md!,
              selectable: true,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            ),
    );
  }
}
