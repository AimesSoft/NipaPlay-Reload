/// Treat API paths as suffixes of a base URL, including its gateway prefix.
Uri appendApiPath(Uri base, String path) => base.replace(
    path: '${base.path.replaceFirst(RegExp(r"/+$"), "")}/'
        '${path.replaceFirst(RegExp(r"^/+"), "")}');
