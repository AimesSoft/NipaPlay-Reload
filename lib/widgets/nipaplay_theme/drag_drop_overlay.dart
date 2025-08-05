import 'package:flutter/material.dart';

class DragDropOverlay extends StatelessWidget {
  const DragDropOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.5),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.movie_creation_outlined,
              color: Colors.white,
              size: 80.0,
            ),
            SizedBox(height: 20.0),
            Text(
              '拖放至页面内播放视频',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24.0,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.none, // 移除MaterialApp之外的文本下划线
              ),
            ),
          ],
        ),
      ),
    );
  }
} 