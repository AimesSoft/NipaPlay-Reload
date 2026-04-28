import 'package:flutter/material.dart';
import 'package:nipaplay/pages/dashboard_home_page.dart';
import 'package:nipaplay/themes/nipaplay/widgets/directional_focus_scope.dart';

class NipaplayLargeScreenHomePage extends StatelessWidget {
  const NipaplayLargeScreenHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const NipaplayDirectionalFocusScope(
      child: DashboardHomePage(),
    );
  }
}
