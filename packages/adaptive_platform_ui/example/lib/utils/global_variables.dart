import 'package:flutter/material.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
BuildContext? get currentContext => navigatorKey.currentContext;

ScrollController homeScrollController = ScrollController();
ScrollController infoScrollController = ScrollController();
ScrollController searchScrollController = ScrollController();
