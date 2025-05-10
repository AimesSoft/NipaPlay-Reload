import 'dart:io'; // Required for File
import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/widgets/cached_network_image_widget.dart'; // Using package import

class AnimeCard extends StatelessWidget {
  final String name;
  final String imageUrl; // Can be a network URL or a local file path
  final VoidCallback onTap;
  final bool isOnAir;

  const AnimeCard({
    super.key,
    required this.name,
    required this.imageUrl,
    required this.onTap,
    this.isOnAir = false,
  });

  @override
  Widget build(BuildContext context) {
    bool isNetworkImage = imageUrl.startsWith('http');
    bool imagePathIsNotEmpty = imageUrl.isNotEmpty;

    Widget imageWidget;
    if (imagePathIsNotEmpty) {
      if (isNetworkImage) {
        imageWidget = CachedNetworkImageWidget(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          width: double.infinity,
        );
      } else {
        // Local file image
        imageWidget = Image.file(
          File(imageUrl),
          fit: BoxFit.cover,
          width: double.infinity,
          errorBuilder: (context, error, stackTrace) {
            // Fallback for local file load error
            return Container(
              color: Colors.grey[800]?.withOpacity(0.5),
              child: const Center(
                child: Icon(
                  Ionicons.image_outline,
                  color: Colors.white30,
                  size: 40,
                ),
              ),
            );
          },
        );
      }
    } else {
      // Placeholder for empty imageUrl
      imageWidget = Container(
        color: Colors.grey[800]?.withOpacity(0.5),
        child: const Center(
          child: Icon(
            Ionicons.image_outline,
            color: Colors.white30,
            size: 40,
          ),
        ),
      );
    }

    return Card(
      elevation: 2.0,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      clipBehavior: Clip.antiAlias,
      color: Colors.transparent, // Make card background transparent
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12), // Match shape for ripple effect
        child: GlassmorphicContainer(
          width: double.infinity,
          height: double.infinity,
          borderRadius: 12,
          blur: 10,
          alignment: Alignment.bottomCenter,
          border: 0.5,
          linearGradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.surface.withOpacity(0.1),
              Theme.of(context).colorScheme.surface.withOpacity(0.2),
            ],
            stops: const [0.1, 1],
          ),
          borderGradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.2),
              Colors.white.withOpacity(0.2),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 7,
                child: imageWidget, // Use the determined image widget
              ),
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.all(6.0),
                  child: Center(
                    child: Text(
                      name,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: 12,
                            height: 1.2,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              if (isOnAir)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4.0, right: 4.0),
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: Icon(Ionicons.time_outline, color: Colors.greenAccent.withOpacity(0.8), size: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
} 