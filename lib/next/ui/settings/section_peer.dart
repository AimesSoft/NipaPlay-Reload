import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../mesh/nipa_peers.dart';
import '../theme/tokens.dart';
import '../widgets/icons.dart';
import 'controls.dart';

/// Nipa on a device that cannot run her: the devices of the account whose
/// Nipa runs, and the one chosen to serve this device. There is no model to
/// set up here; the device chosen has its own.
class NipaPeerSection extends StatefulWidget {
  const NipaPeerSection({super.key, required this.peers});
  final NipaPeers peers;

  @override
  State<NipaPeerSection> createState() => _NipaPeerSectionState();
}

class _NipaPeerSectionState extends State<NipaPeerSection> {
  StreamSubscription<void>? _changes;
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    _changes = widget.peers.changes.listen((_) {
      if (mounted) setState(() {});
    });
    unawaited(widget.peers.refresh().whenComplete(() {
      if (mounted) setState(() => _asked = true);
    }));
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  String _state(NipaPeer peer) {
    if (!peer.online) return '不在线';
    if (!peer.runs) return '没有运行 Nipa';
    return peer.busy ? '忙' : '空闲';
  }

  @override
  Widget build(BuildContext context) {
    final peers = widget.peers;
    final list = peers.peers;
    if (list.isEmpty) {
      return SettingsCard(children: [
        SettingsRow(
          title: _asked ? '没有设备在运行 Nipa' : '正在查找',
        ),
      ]);
    }
    return SettingsCard(children: [
      for (final peer in list)
        SettingsRow(
          key: ValueKey(peer.id),
          leading: StateDot(peer.usable ? NextColors.mint : NextColors.p4,
              glow: peer.usable),
          title: peer.name,
          subtitle: _state(peer),
          onTap: () =>
              unawaited(peers.choose(peers.chosen == peer.id ? null : peer.id)),
          trailing: peers.chosen == peer.id
              ? const NextIcon(NextGlyph.check,
                  size: 18, color: NextColors.mint)
              : null,
        ),
    ]);
  }
}
