import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';

import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CanvasDanmaku Demo',
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late DanmakuController _controller;
  var _key = new GlobalKey<ScaffoldState>();

  final _danmuKey = GlobalKey();

  bool _running = true;

  /// 弹幕描边
  bool _showStroke = true;

  /// 弹幕海量模式(弹幕轨道填满时继续绘制)
  bool _massiveMode = false;

  /// 弹幕透明度
  double _opacity = 1.0;

  /// 弹幕持续时间
  int _duration = 8;

  /// 弹幕字号
  double _fontSize = (Platform.isIOS || Platform.isAndroid) ? 16 : 25;

  /// 隐藏滚动弹幕
  bool _hideScroll = false;

  /// 隐藏顶部弹幕
  bool _hideTop = false;

  /// 隐藏底部弹幕
  bool _hideBottom = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _key,
      appBar: AppBar(
        title: Text('CanvasDanmaku Demo'),
        actions: [
          IconButton(
            icon: Icon(Icons.add),
            tooltip: 'Add Scroll',
            onPressed: () {
              _controller.addDanmaku(
                DanmakuContentItem(
                    "这是一条超长弹幕ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789这是一条超长的弹幕，这条弹幕会超出屏幕宽度",
                    color: getRandomColor()),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.add),
            tooltip: 'Add Top',
            onPressed: () {
              _controller.addDanmaku(
                DanmakuContentItem("这是一条顶部弹幕",
                    color: getRandomColor(), type: DanmakuItemType.top),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.add),
            tooltip: 'Add Bottom',
            onPressed: () {
              _controller.addDanmaku(
                DanmakuContentItem("这是一条底部弹幕",
                    color: getRandomColor(), type: DanmakuItemType.bottom),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.play_circle_outline_outlined),
            onPressed: startPlay,
            tooltip: 'Start Player',
          ),
          IconButton(
            icon: Icon(_running ? Icons.pause : Icons.play_arrow),
            onPressed: () {
              if (_running) {
                _controller.pause();
              } else {
                _controller.resume();
              }
              setState(() {
                _running = !_running;
              });
            },
            tooltip: 'Play Resume',
          ),
          IconButton(
            icon: Icon(_showStroke
                ? Icons.font_download
                : Icons.font_download_rounded),
            onPressed: () {
              _controller.updateOption(
                  _controller.option.copyWith(showStroke: !_showStroke));
              setState(() {
                _showStroke = !_showStroke;
              });
            },
            tooltip: 'Stroke',
          ),
          IconButton(
            icon: Icon(Icons.clear),
            onPressed: () {
              _controller.clear();
            },
            tooltip: 'Clear',
          ),
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () {
              _key.currentState?.openEndDrawer();
            },
            tooltip: 'Settings',
          ),
        ],
      ),
      backgroundColor: Colors.grey,
      body: DanmakuScreen(
        key: _danmuKey,
        createdController: (DanmakuController e) {
          _controller = e;
        },
        option: DanmakuOption(
          opacity: _opacity,
          fontSize: _fontSize,
          duration: _duration,
          showStroke: _showStroke,
          massiveMode: _massiveMode,
          hideScroll: _hideScroll,
          hideTop: _hideTop,
          hideBottom: _hideBottom,
        ),
      ),
      endDrawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.all(8),
            children: [
              Text("Opacity : $_opacity"),
              Slider(
                value: _opacity,
                max: 1.0,
                min: 0.1,
                divisions: 9,
                onChanged: (e) {
                  setState(() {
                    _opacity = e;
                  });
                  _controller
                      .updateOption(_controller.option.copyWith(opacity: e));
                },
              ),
              Text("FontSize : $_fontSize"),
              Slider(
                value: _fontSize,
                min: 8,
                max: 36,
                divisions: 14,
                onChanged: (e) {
                  setState(() {
                    _fontSize = e;
                  });
                  _controller
                      .updateOption(_controller.option.copyWith(fontSize: e));
                },
              ),
              Text("Duration : $_duration"),
              Slider(
                value: _duration.toDouble(),
                min: 4,
                max: 20,
                divisions: 16,
                onChanged: (e) {
                  setState(() {
                    _duration = e.toInt();
                  });
                  _controller.updateOption(
                      _controller.option.copyWith(duration: e.toInt()));
                },
              ),
              SwitchListTile(
                  title: Text('MassiveMode'),
                  value: _massiveMode,
                  onChanged: (e) {
                    setState(() {
                      _massiveMode = e;
                    });
                    _controller.updateOption(
                        _controller.option.copyWith(massiveMode: e));
                  })
            ],
          ),
        ),
      ),
    );
  }

  Timer? timer;
  int sec = 0;
  void startPlay() async {
    String data = await rootBundle.loadString('assets/132590001.json');
    List<DanmakuContentItem> _items = [];
    var jsonMap = json.decode(data);
    for (var item in jsonMap['comments']) {
      _items.add(DanmakuContentItem(
        item['m'],
        color: Colors.white,
      ));
    }
    if (timer == null) {
      timer = Timer.periodic(Duration(seconds: 1), (timer) {
        if (!_controller.running) return;
        _controller.addDanmaku(_items[sec]);
        sec++;
      });
    }
  }

  // 生成随机颜色
  Color getRandomColor() {
    final Random random = Random();
    return Color.fromARGB(
      255, // 固定 alpha 为 255（完全不透明）
      random.nextInt(256),
      random.nextInt(256),
      random.nextInt(256),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }
}
