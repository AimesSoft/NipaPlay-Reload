
part of "media_sources_page.dart";


class MediaSourceFilesPage extends StatelessWidget {
  const MediaSourceFilesPage({
    super.key,
    required this.folder,
  });

  final Directory folder;

  Future<List<File>> _loadFiles() async {
    final directory = folder;

    if (!await directory.exists()) {
      throw FileSystemException(
        '文件夹不存在',
        folder.path,
      );
    }

    final files = <File>[];

    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        files.add(entity);
      }
    }

    files.sort(
      (a, b) => a.path.compareTo(b.path),
    );

    return files;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(p.basename(folder.path)),
      ),
      body: FutureBuilder<List<File>>(
        future: _loadFiles(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '读取文件夹失败：\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final files = snapshot.data ?? [];

          if (files.isEmpty) {
            return const Center(
              child: Text('文件夹内没有文件'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: files.length,
            itemBuilder: (context, index) {
              final file = files[index];

              return ListTile(
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(
                  p.basename(file.path),
                ),
                subtitle: Text(
                  p.relative(
                    file.path,
                    from: folder.path,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}