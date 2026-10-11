import 'package:flutter/material.dart';
import 'credential_store.dart';

final class CredentialNotice extends StatelessWidget {
  const CredentialNotice({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<String>>(
        valueListenable: CredentialStore.instance.notices,
        builder: (context, notices, _) => Column(children: [
          if (notices.isNotEmpty)
            Material(
              color: const Color(0xffffe0b2),
              child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(notices.join('\n'),
                          style: const TextStyle(
                              color: Colors.black, fontSize: 13)),
                      for (final ref
                          in CredentialStore.instance.vault.blocked.keys)
                        TextButton(
                            onPressed: () async {
                              try {
                                await CredentialStore.instance.retry(ref);
                              } catch (_) {
                                // The store publishes the new authorization outcome.
                              }
                            },
                            child: Text('重试 $ref')),
                    ]),
                  )),
            ),
          Expanded(child: child),
        ]),
      );
}
