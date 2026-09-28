import 'package:flutter/material.dart';
import 'package:nipaplay/plugins/url_resolver.dart';

class PluginUrlSelectionContent extends StatefulWidget {
  const PluginUrlSelectionContent({
    super.key,
    required this.title,
    required this.items,
    this.preferredId,
  });

  final String title;
  final List<PluginUrlChoice> items;
  final String? preferredId;

  @override
  State<PluginUrlSelectionContent> createState() =>
      _PluginUrlSelectionContentState();
}

class _PluginUrlSelectionContentState extends State<PluginUrlSelectionContent> {
  late final int _preferredIndex;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    final index =
        widget.items.indexWhere((item) => item.id == widget.preferredId);
    _preferredIndex = index < 0 ? 0 : index;
    _scrollController =
        ScrollController(initialScrollOffset: _preferredIndex * 72);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: SizedBox(
          width: 520,
          height: MediaQuery.sizeOf(context).height * 0.5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 12),
              Expanded(
                  child: ListView.builder(
                controller: _scrollController,
                itemExtent: 72,
                itemCount: widget.items.length,
                itemBuilder: (_, index) {
                  final item = widget.items[index];
                  return ListTile(
                    autofocus: index == _preferredIndex,
                    title: Text(item.title,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.of(context).pop(item.id),
                  );
                },
              )),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
            ],
          ),
        ),
      );
}
