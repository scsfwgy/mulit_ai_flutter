import 'package:flutter/cupertino.dart';

import 'package:mulit_ai_flutter/core/app_preferences.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';
import 'package:mulit_ai_flutter/search/search_service.dart';

class SearchSources extends StatefulWidget {
  const SearchSources({super.key, required this.sources, required this.onOpen});
  final List<SearchSource> sources;
  final ValueChanged<String> onOpen;
  @override
  State<SearchSources> createState() => _SearchSourcesState();
}

class _SearchSourcesState extends State<SearchSources> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      CupertinoButton(
        padding: const EdgeInsets.symmetric(vertical: 6),
        minimumSize: const Size(0, 34),
        onPressed: () => setState(() => _expanded = !_expanded),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.globe, size: 14, color: IosColors.blue),
            const SizedBox(width: 5),
            Text(
              '${tr('搜索来源')} · ${widget.sources.length}',
              style: TextStyle(color: IosColors.blue, fontSize: 12),
            ),
            const SizedBox(width: 5),
            Icon(
              _expanded
                  ? CupertinoIcons.chevron_up
                  : CupertinoIcons.chevron_down,
              size: 12,
              color: IosColors.blue,
            ),
          ],
        ),
      ),
      if (_expanded)
        for (var i = 0; i < widget.sources.length; i++)
          CupertinoButton(
            padding: const EdgeInsets.symmetric(vertical: 5),
            minimumSize: const Size(0, 40),
            onPressed: () => widget.onOpen(widget.sources[i].url),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${i + 1}. ${widget.sources[i].title}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: IosColors.blue, fontSize: 13),
                ),
                Text(
                  Uri.parse(widget.sources[i].url).host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: IosColors.secondary, fontSize: 11),
                ),
              ],
            ),
          ),
    ],
  );
}
