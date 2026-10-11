import 'package:flutter/widgets.dart';
import 'package:nipaplay/pages/dashboard_home_page.dart';

DashboardHomeAccess? classicHome() {
  DashboardHomeAccess? found;
  void visit(Element element) {
    if (element is StatefulElement && element.state is DashboardHomeAccess) {
      found = element.state as DashboardHomeAccess;
    }
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}
