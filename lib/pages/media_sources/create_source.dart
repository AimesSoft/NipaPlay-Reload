part of "media_sources_page.dart";

Future<MediaSourceInfo?> createOrEditMediaSourceDialog(BuildContext context, {MediaSourceInfo? info}) async {

  final titleController = TextEditingController(text: info?.id.toString() ?? '');
  final descriptionController = TextEditingController(text: info?.name ?? '');
  final pathController = TextEditingController(text: info is LocalMediaSourceInfo ? info.directory.path : '');

  return NipaplayWindow.show<MediaSourceInfo>(
    context: context,
    child: NipaplayWindowScaffold(
      maxWidth: 500,
      maxHeightFactor: 0.5,
      onClose: () {
        Navigator.of(context).pop();
      },
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            const Text(
              '新建媒体源',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),

            // 输入 ID, 类型是整数
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'ID',
                hintText: '请输入媒体源 ID',
              ),
            ),
            const SizedBox(height: 20),

            // 输入名称
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(
                labelText: '媒体源名称',
                hintText: '请输入媒体源名称',
              ),
            ),
            const SizedBox(height: 20),

            // 输入路径
            TextField(
              controller: pathController,
              decoration: const InputDecoration(
                labelText: '媒体源路径',
                hintText: '请输入媒体源路径',
              ),
            ),

            ElevatedButton(
              onPressed: () {

                final id = titleController.text.trim();
                final name = descriptionController.text.trim();
                final path = pathController.text.trim();

                if (id.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('媒体源 ID 不能为空')),
                  );
                  return;
                }
                final newMediaSource = LocalMediaSourceInfo(
                  id: int.parse(id),
                  name: name,
                  directory: Directory(path),
                );
                Navigator.of(context).pop(newMediaSource);
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    ),
  );
}