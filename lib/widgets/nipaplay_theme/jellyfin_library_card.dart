import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/services/jellyfin_service.dart';

class JellyfinLibraryCard extends StatelessWidget {
  final JellyfinLibrary library;
  final VoidCallback onTap;

  const JellyfinLibraryCard({
    super.key,
    required this.library,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final jellyfinService = JellyfinService.instance;
    final imageUrl = library.imageTagsPrimary != null
        ? jellyfinService.getImageUrl(library.id, width: 600)
        : '';

    return Card(
      elevation: 8,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 16 / 9, // 强制长方形比例
          child: Stack(
            children: [
              // 背景图片或随机渐变背景
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: _getRandomGradient(),
                  ),
                  child: imageUrl.isNotEmpty
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              decoration: BoxDecoration(
                                gradient: _getRandomGradient(),
                              ),
                            );
                          },
                        )
                      : null,
                ),
              ),
              // 半透明覆盖层确保文字清晰
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.1),
                        Colors.black.withOpacity(0.5),
                      ],
                    ),
                  ),
                ),
              ),
              // 文字内容
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _getLibraryIcon(library.type),
                            size: 24,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              library.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(
                                    color: Colors.black87,
                                    offset: Offset(0, 2),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (library.totalItems != null && library.totalItems! > 0) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${library.totalItems} 项内容',
                          locale:Locale("zh","CN"),
style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            shadows: const [
                              Shadow(
                                color: Colors.black54,
                                offset: Offset(0, 1),
                                blurRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 生成随机渐变背景
  LinearGradient _getRandomGradient() {
    final gradients = [
      LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.blue[700]!, Colors.purple[700]!],
      ),
      LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.orange[700]!, Colors.red[700]!],
      ),
      LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.green[700]!, Colors.teal[700]!],
      ),
      LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.indigo[700]!, Colors.blue[700]!],
      ),
      LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.pink[700]!, Colors.purple[700]!],
      ),
      LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.cyan[700]!, Colors.blue[700]!],
      ),
    ];
    
    // 使用媒体库ID的哈希值来确保同一个媒体库总是显示相同的颜色
    final index = library.id.hashCode.abs() % gradients.length;
    return gradients[index];
  }

  IconData _getLibraryIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'movies':
        return Icons.movie;
      case 'tvshows':
        return Icons.tv;
      case 'music':
        return Icons.music_note;
      case 'books':
        return Icons.book;
      case 'photos':
        return Icons.photo;
      default:
        return Icons.folder;
    }
  }
}
