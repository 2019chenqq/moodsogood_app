import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class SimpleWebPage extends StatefulWidget {
  final String title;
  final String url;
  const SimpleWebPage({super.key, required this.title, required this.url});

  @override
  State<SimpleWebPage> createState() => _SimpleWebPageState();
}

class _SimpleWebPageState extends State<SimpleWebPage> {
  late final WebViewController _c;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => setState(() => _loading = false),
      ))
      ..loadRequest(Uri.parse(widget.url.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(children: [
        WebViewWidget(controller: _c),
        if (_loading) const Center(child: CircularProgressIndicator()),
      ]),
    );
  }
}
