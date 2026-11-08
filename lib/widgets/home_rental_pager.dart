import 'package:flutter/material.dart';

import 'liquid_glass.dart';

/// One compact surface with vertical paging for every rental.
class HomeRentalPager extends StatefulWidget {
  const HomeRentalPager({
    super.key,
    required this.title,
    required this.itemCount,
    required this.itemBuilder,
    required this.contentHeight,
  });

  final String title;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double contentHeight;

  @override
  State<HomeRentalPager> createState() => _HomeRentalPagerState();
}

class _HomeRentalPagerState extends State<HomeRentalPager> {
  final _controller = PageController();
  int _index = 0;

  @override
  void didUpdateWidget(HomeRentalPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_index >= widget.itemCount) {
      _index = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.hasClients) _controller.jumpToPage(0);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      margin: const EdgeInsets.fromLTRB(18, 8, 18, 10),
      borderRadius: 22,
      blurSigma: 3,
      glowColor: const Color(0xFFDF762D),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(widget.title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.3)),
                  ),
                  const SizedBox(width: 12),
                  Semantics(
                    liveRegion: true,
                    label: 'Rental ${_index + 1} of ${widget.itemCount}',
                    child: ExcludeSemantics(
                      child: Text('${_index + 1} / ${widget.itemCount}',
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant)),
                    ),
                  ),
                ]),
              ],
            ),
          ),
          SizedBox(
            height: widget.contentHeight,
            child: PageView.builder(
              key: const ValueKey('home-rental-pages'),
              controller: _controller,
              scrollDirection: Axis.vertical,
              allowImplicitScrolling: true,
              itemCount: widget.itemCount,
              onPageChanged: (value) => setState(() => _index = value),
              itemBuilder: widget.itemBuilder,
            ),
          ),
        ],
      ),
    );
  }
}
