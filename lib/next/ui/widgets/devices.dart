import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../theme/tokens.dart';
import 'icons.dart';

/// Where something is besides this device: a small screen and the device's
/// name, nothing more.
class DeviceMark extends StatelessWidget {
  const DeviceMark(this.devices, {super.key, this.size = 12});
  final List<UiDevice> devices;
  final double size;

  @override
  Widget build(BuildContext context) => Text.rich(
        TextSpan(style: NextText.sans(size, color: NextColors.p3), children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: EdgeInsets.only(right: size * 0.42),
              child: NextIcon(NextGlyph.device,
                  size: size, color: NextColors.p3, stroke: 1.9),
            ),
          ),
          TextSpan(text: devices.map((d) => d.name).join(' · ')),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
}
