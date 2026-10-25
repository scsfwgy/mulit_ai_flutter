import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mulit_ai_flutter/core/project.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

class KnowledgeSources extends StatefulWidget {
  const KnowledgeSources({super.key, required this.sources});
  final List<KnowledgeSource> sources;
  @override
  State<KnowledgeSources> createState() => _KnowledgeSourcesState();
}

class _KnowledgeSourcesState extends State<KnowledgeSources> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CupertinoButton(
        padding: const EdgeInsets.symmetric(vertical: 5),
        minimumSize: const Size(0, 34),
        onPressed: () => setState(() => _expanded = !_expanded),
        child: Text(
          F('i18n.knowledge_sources_count', [widget.sources.length]),
          style: TextStyle(color: IosColors.blue, fontSize: 12),
        ),
      ),
      if (_expanded)
        for (final source in widget.sources)
          CupertinoButton(
            padding: const EdgeInsets.symmetric(vertical: 4),
            onPressed: () => Navigator.of(context).push(
              appPageRoute<void>(
                builder: (_) => Scaffold(
                  backgroundColor: IosColors.background,
                  appBar: iosAppBar(title: '${source.name} · ${source.label}'),
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      source.text,
                      style: TextStyle(color: IosColors.label),
                    ),
                  ),
                ),
              ),
            ),
            child: Text(
              '[${source.label}] ${source.name}',
              style: TextStyle(color: IosColors.blue, fontSize: 12),
            ),
          ),
    ],
  );
}
