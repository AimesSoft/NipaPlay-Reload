import 'package:nipaplay/remote/shared_remote_host_selection_model.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_group_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';

class CupertinoSharedRemoteHostSelectionView extends StatelessWidget {
  const CupertinoSharedRemoteHostSelectionView({
    super.key,
    required this.data,
  });

  final SharedRemoteHostSelectionViewModel data;

  @override
  Widget build(BuildContext context) {
    final background = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final secondary = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    return CupertinoBottomSheetContentLayout(
      backgroundColor: background,
      sliversBuilder: (context, topSpacing) => [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(0, topSpacing + 14, 0, 28),
          sliver: SliverList(
            delegate: SliverChildListDelegate.fixed([
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  SharedRemoteHostSelectionViewModel.description,
                  style:
                      TextStyle(fontSize: 14, color: secondary, height: 1.35),
                ),
              ),
              const SizedBox(height: 18),
              _buildActions(context),
              const SizedBox(height: 22),
              if (data.items.isEmpty)
                _buildEmpty(context)
              else
                _buildHosts(context),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    return CupertinoSettingsGroupCard(
      addDividers: true,
      children: [
        for (final action in data.actions)
          CupertinoSettingsTile(
            leading: Icon(
              _iconForAction(action.kind),
              color: resolveSettingsIconColor(context),
            ),
            title: Text(action.label),
            showChevron: true,
            onTap: action.enabled ? () => action.onPressed() : null,
          ),
      ],
    );
  }

  Widget _buildHosts(BuildContext context) {
    final secondary = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    return CupertinoSettingsGroupCard(
      addDividers: true,
      children: [
        for (final item in data.items)
          CupertinoSettingsTile(
            leading: Icon(
              item.isOnline
                  ? CupertinoIcons.desktopcomputer
                  : CupertinoIcons.desktopcomputer,
              color: secondary,
            ),
            title: Text(item.displayName),
            subtitle: Text(
              item.errorMessage?.trim().isNotEmpty == true
                  ? item.errorMessage!
                  : '${item.baseUrl}\n${item.lastConnectedLabel}',
            ),
            selected: item.isActive,
            showChevron: !item.isActive,
            onTap: () => item.onSelect(),
          ),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final secondary = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    return CupertinoSettingsGroupCard(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          child: Column(
            children: [
              Icon(CupertinoIcons.desktopcomputer, size: 36, color: secondary),
              const SizedBox(height: 10),
              Text('尚未添加共享客户端', style: TextStyle(color: secondary)),
            ],
          ),
        ),
      ],
    );
  }

  IconData _iconForAction(SharedRemoteHostSelectionActionKind kind) {
    return switch (kind) {
      SharedRemoteHostSelectionActionKind.scanLan =>
        CupertinoIcons.dot_radiowaves_left_right,
      SharedRemoteHostSelectionActionKind.scanQr =>
        CupertinoIcons.qrcode_viewfinder,
      SharedRemoteHostSelectionActionKind.addManually => CupertinoIcons.add,
    };
  }
}
