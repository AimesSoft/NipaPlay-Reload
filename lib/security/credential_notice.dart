import 'package:flutter/material.dart';
import 'credential_store.dart';

/// The one banner for the vault as a whole. An entry that is only missing is
/// shown where it belongs, on the connection or account that owns it.
final class CredentialNotice extends StatelessWidget {
  const CredentialNotice({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final store = CredentialStore.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([store.notices, store.dismissed]),
      builder: (context, _) {
        final lines = [
          for (final line in store.notices.value)
            if (!store.dismissed.value.contains(line)) line,
        ];
        return Column(children: [
          if (lines.isNotEmpty)
            Material(
              color: const Color(0xffffe0b2),
              child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                    child: Row(children: [
                      Expanded(
                        child: Text(lines.join('\n'),
                            style: const TextStyle(
                                color: Colors.black, fontSize: 13)),
                      ),
                      if (store.failures.isNotEmpty)
                        TextButton(
                            onPressed: store.retryVault,
                            child: const Text('重试')),
                      IconButton(
                          tooltip: '关闭',
                          iconSize: 18,
                          color: Colors.black54,
                          onPressed: store.dismiss,
                          icon: const Icon(Icons.close)),
                    ]),
                  )),
            ),
          Expanded(child: child),
        ]);
      },
    );
  }
}
