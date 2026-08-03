import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

enum RemoteTextInputSessionStatus {
  pending,
  submitted,
  cancelled,
  expired,
}

class RemoteTextInputField {
  const RemoteTextInputField({
    required this.id,
    required this.title,
    required this.initialValue,
    this.obscureText = false,
    this.multiline = false,
    this.inputType = 'text',
    this.maxLength,
    this.required = false,
  });

  final String id;
  final String title;
  final String initialValue;
  final bool obscureText;
  final bool multiline;
  final String inputType;
  final int? maxLength;
  final bool required;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'initialValue': obscureText ? '' : initialValue,
      'hasInitialValue': initialValue.isNotEmpty,
      'obscureText': obscureText,
      'multiline': multiline,
      'inputType': inputType,
      if (maxLength != null) 'maxLength': maxLength,
      'required': required,
    };
  }
}

class RemoteTextInputSubmission {
  const RemoteTextInputSubmission(this.values);

  final Map<String, String> values;
}

class RemoteTextInputSession {
  RemoteTextInputSession({
    required this.key,
    required this.title,
    required this.fields,
    required this.createdAt,
    required this.expiresAt,
  });

  final String key;
  final String title;
  final List<RemoteTextInputField> fields;
  final DateTime createdAt;
  final DateTime expiresAt;
  final Completer<RemoteTextInputSubmission?> _submissionCompleter =
      Completer<RemoteTextInputSubmission?>();

  RemoteTextInputSessionStatus status = RemoteTextInputSessionStatus.pending;
  Map<String, String>? submittedValues;

  RemoteTextInputField get primaryField => fields.first;
  String get initialValue => primaryField.initialValue;
  bool get obscureText => primaryField.obscureText;
  bool get multiline => primaryField.multiline;
  String get inputType => primaryField.inputType;
  int? get maxLength => primaryField.maxLength;
  String? get submittedValue => submittedValues?[primaryField.id];

  Future<RemoteTextInputSubmission?> get submissionResult =>
      _submissionCompleter.future;
  Future<String?> get result => submissionResult
      .then((submission) => submission?.values[primaryField.id]);
  bool get isPending => status == RemoteTextInputSessionStatus.pending;

  String get displayKey {
    final visible = key.substring(0, min(8, key.length)).toUpperCase();
    if (visible.length <= 4) return visible;
    return '${visible.substring(0, 4)}-${visible.substring(4)}';
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'success': true,
      'key': key,
      'displayKey': displayKey,
      'title': title,
      'initialValue': obscureText ? '' : initialValue,
      'obscureText': obscureText,
      'multiline': multiline,
      'inputType': inputType,
      if (maxLength != null) 'maxLength': maxLength,
      'fields': fields.map((field) => field.toJson()).toList(growable: false),
      'status': status.name,
      'expiresAt': expiresAt.toUtc().toIso8601String(),
    };
  }

  void submit(String value) {
    submitValues(<String, String>{primaryField.id: value});
  }

  void submitValues(Map<String, String> values) {
    if (!isPending) return;
    submittedValues = Map<String, String>.unmodifiable(values);
    status = RemoteTextInputSessionStatus.submitted;
    _submissionCompleter.complete(
      RemoteTextInputSubmission(submittedValues!),
    );
  }

  void cancel() {
    if (!isPending) return;
    status = RemoteTextInputSessionStatus.cancelled;
    _submissionCompleter.complete(null);
  }

  void expire() {
    if (!isPending) return;
    status = RemoteTextInputSessionStatus.expired;
    _submissionCompleter.complete(null);
  }
}

class RemoteTextInputRequest {
  const RemoteTextInputRequest({
    required this.uri,
    required this.key,
  });

  final Uri uri;
  final String key;
}

class RemoteTextInputMetadata {
  const RemoteTextInputMetadata({
    required this.key,
    required this.displayKey,
    required this.title,
    required this.fields,
  });

  final String key;
  final String displayKey;
  final String title;
  final List<RemoteTextInputFieldMetadata> fields;

  RemoteTextInputFieldMetadata get primaryField => fields.first;
  String get initialValue => primaryField.initialValue;
  bool get obscureText => primaryField.obscureText;
  bool get multiline => primaryField.multiline;
  String get inputType => primaryField.inputType;
  int? get maxLength => primaryField.maxLength;

  factory RemoteTextInputMetadata.fromJson(Map<String, dynamic> json) {
    final rawFields = json['fields'];
    final fields = rawFields is List
        ? rawFields
            .whereType<Map>()
            .map(
              (field) => RemoteTextInputFieldMetadata.fromJson(
                Map<String, dynamic>.from(field),
              ),
            )
            .toList(growable: false)
        : <RemoteTextInputFieldMetadata>[];
    return RemoteTextInputMetadata(
      key: json['key']?.toString() ?? '',
      displayKey: json['displayKey']?.toString() ?? '',
      title: json['title']?.toString() ?? '远程输入',
      fields: fields.isNotEmpty
          ? fields
          : <RemoteTextInputFieldMetadata>[
              RemoteTextInputFieldMetadata(
                id: 'value',
                title: json['title']?.toString() ?? '远程输入',
                initialValue: json['initialValue']?.toString() ?? '',
                hasInitialValue:
                    (json['initialValue']?.toString() ?? '').isNotEmpty,
                obscureText: json['obscureText'] == true,
                multiline: json['multiline'] == true,
                inputType: json['inputType']?.toString() ?? 'text',
                maxLength: (json['maxLength'] as num?)?.toInt(),
                required: false,
              ),
            ],
    );
  }
}

class RemoteTextInputFieldMetadata {
  const RemoteTextInputFieldMetadata({
    required this.id,
    required this.title,
    required this.initialValue,
    required this.hasInitialValue,
    required this.obscureText,
    required this.multiline,
    required this.inputType,
    required this.maxLength,
    required this.required,
  });

  final String id;
  final String title;
  final String initialValue;
  final bool hasInitialValue;
  final bool obscureText;
  final bool multiline;
  final String inputType;
  final int? maxLength;
  final bool required;

  factory RemoteTextInputFieldMetadata.fromJson(Map<String, dynamic> json) {
    return RemoteTextInputFieldMetadata(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '输入文字',
      initialValue: json['initialValue']?.toString() ?? '',
      hasInitialValue: json['hasInitialValue'] == true,
      obscureText: json['obscureText'] == true,
      multiline: json['multiline'] == true,
      inputType: json['inputType']?.toString() ?? 'text',
      maxLength: (json['maxLength'] as num?)?.toInt(),
      required: json['required'] == true,
    );
  }
}

class RemoteTextInputService {
  RemoteTextInputService._();

  static final RemoteTextInputService instance = RemoteTextInputService._();
  static const Duration defaultLifetime = Duration(minutes: 10);
  static const int absoluteMaxLength = 65536;

  final Random _random = Random.secure();
  final Map<String, RemoteTextInputSession> _sessions =
      <String, RemoteTextInputSession>{};

  RemoteTextInputSession createSession({
    required String title,
    required String initialValue,
    bool obscureText = false,
    bool multiline = false,
    String inputType = 'text',
    int? maxLength,
    Duration lifetime = defaultLifetime,
  }) {
    return createGroupSession(
      title: title,
      fields: <RemoteTextInputField>[
        RemoteTextInputField(
          id: 'value',
          title: title,
          initialValue: initialValue,
          obscureText: obscureText,
          multiline: multiline,
          inputType: inputType,
          maxLength: maxLength,
        ),
      ],
      lifetime: lifetime,
    );
  }

  RemoteTextInputSession createGroupSession({
    required String title,
    required List<RemoteTextInputField> fields,
    Duration lifetime = defaultLifetime,
  }) {
    if (fields.isEmpty) {
      throw ArgumentError.value(fields, 'fields', '不能为空');
    }
    _pruneExpired();
    var key = _generateKey();
    while (_sessions.containsKey(key)) {
      key = _generateKey();
    }
    final now = DateTime.now();
    final normalizedFields = <RemoteTextInputField>[];
    final usedIds = <String>{};
    for (var index = 0; index < fields.length; index++) {
      final field = fields[index];
      var id = field.id.trim().isEmpty ? 'field_$index' : field.id.trim();
      if (!usedIds.add(id)) {
        id = 'field_$index';
        usedIds.add(id);
      }
      final maxLength = field.maxLength?.clamp(1, absoluteMaxLength).toInt();
      normalizedFields.add(
        RemoteTextInputField(
          id: id,
          title: field.title.trim().isEmpty ? '输入文字' : field.title.trim(),
          initialValue: field.initialValue,
          obscureText: field.obscureText,
          multiline: field.multiline,
          inputType: field.inputType,
          maxLength: maxLength,
          required: field.required,
        ),
      );
    }
    final session = RemoteTextInputSession(
      key: key,
      title: title.trim().isEmpty ? '远程输入' : title.trim(),
      fields: List<RemoteTextInputField>.unmodifiable(normalizedFields),
      createdAt: now,
      expiresAt: now.add(lifetime),
    );
    _sessions[key] = session;
    return session;
  }

  RemoteTextInputSession? sessionForKey(String key) {
    _pruneExpired();
    return _sessions[key];
  }

  void cancelSession(String key) {
    sessionForKey(key)?.cancel();
  }

  Uri buildInputUri(String baseUrl, RemoteTextInputSession session) {
    final normalized = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$normalized/api/remote/input/${session.key}');
  }

  void clearForTesting() {
    for (final session in _sessions.values) {
      session.cancel();
    }
    _sessions.clear();
  }

  String _generateKey() {
    final bytes = List<int>.generate(18, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  void _pruneExpired() {
    final now = DateTime.now();
    final removable = <String>[];
    for (final entry in _sessions.entries) {
      final session = entry.value;
      if (session.isPending && now.isAfter(session.expiresAt)) {
        session.expire();
      }
      if (!session.isPending &&
          now.difference(session.expiresAt).inMinutes > 1) {
        removable.add(entry.key);
      }
    }
    for (final key in removable) {
      _sessions.remove(key);
    }
  }
}

class RemoteTextInputClientService {
  const RemoteTextInputClientService._();

  static RemoteTextInputRequest? tryParseScannedText(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return null;
    }
    final segments = uri.pathSegments;
    if (segments.length < 4) return null;
    final offset = segments.length - 4;
    if (segments[offset] != 'api' ||
        segments[offset + 1] != 'remote' ||
        segments[offset + 2] != 'input') {
      return null;
    }
    final key = segments[offset + 3].trim();
    if (key.isEmpty || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(key)) {
      return null;
    }
    return RemoteTextInputRequest(
      uri: uri.replace(query: null, fragment: null),
      key: key,
    );
  }

  static Future<RemoteTextInputMetadata> fetchMetadata(
    RemoteTextInputRequest request,
  ) async {
    final response = await http.get(
      request.uri.replace(queryParameters: const <String, String>{
        'format': 'json',
      }),
      headers: const <String, String>{'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 6));
    final decoded = json.decode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200 || decoded is! Map) {
      throw StateError('远程输入会话不可用');
    }
    final payload = Map<String, dynamic>.from(decoded);
    if (payload['success'] != true || payload['status'] != 'pending') {
      throw StateError(payload['message']?.toString() ?? '远程输入会话已失效');
    }
    return RemoteTextInputMetadata.fromJson(payload);
  }

  static Future<void> submit(
    RemoteTextInputRequest request,
    String value,
  ) async {
    return submitValues(
      request,
      <String, String>{'value': value},
      useLegacyValue: true,
    );
  }

  static Future<void> submitValues(
    RemoteTextInputRequest request,
    Map<String, String> values, {
    bool useLegacyValue = false,
  }) async {
    final response = await http
        .post(
          request.uri,
          headers: const <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: json.encode(
            useLegacyValue
                ? <String, dynamic>{
                    'value': values.isEmpty ? '' : values.values.first,
                  }
                : <String, dynamic>{'values': values},
          ),
        )
        .timeout(const Duration(seconds: 8));
    final decoded = json.decode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200 ||
        decoded is! Map ||
        decoded['success'] != true) {
      final message = decoded is Map ? decoded['message']?.toString() : null;
      throw StateError(message ?? '提交远程输入失败');
    }
  }
}

class RemoteTextInputApiService {
  RemoteTextInputApiService() {
    _router.get('/<key>', _handleGet);
    _router.post('/<key>', _handlePost);
  }

  final Router _router = Router();
  final RemoteTextInputService _service = RemoteTextInputService.instance;

  Router get router => _router;

  Response _handleGet(Request request, String key) {
    final session = _service.sessionForKey(key);
    if (session == null) {
      return _error(request, 404, '输入会话不存在或已经过期');
    }
    if (_wantsJson(request)) {
      return _json(session.toJson());
    }
    return _html(_buildInputPage(request, session));
  }

  Future<Response> _handlePost(Request request, String key) async {
    final session = _service.sessionForKey(key);
    if (session == null) {
      return _error(request, 404, '输入会话不存在或已经过期');
    }
    if (!session.isPending) {
      return _error(request, 409, '输入会话已经完成');
    }

    Map<String, String> values;
    try {
      final raw = await request.readAsString();
      if (raw.length >
          RemoteTextInputService.absoluteMaxLength *
              max(4, session.fields.length)) {
        return _error(request, 413, '输入内容过长');
      }
      final contentType = request.headers['content-type'] ?? '';
      if (contentType.contains('application/json')) {
        final decoded = json.decode(raw);
        if (decoded is! Map) throw const FormatException();
        final submittedValues = decoded['values'];
        if (submittedValues is Map) {
          values = submittedValues.map(
            (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
          );
        } else {
          values = <String, String>{
            session.primaryField.id: decoded['value']?.toString() ?? '',
          };
        }
      } else {
        final form = Uri.splitQueryString(raw);
        values = <String, String>{};
        for (var index = 0; index < session.fields.length; index++) {
          values[session.fields[index].id] = form['field_$index'] ?? '';
        }
      }
    } catch (_) {
      return _error(request, 400, '无法解析输入内容');
    }

    final normalizedValues = <String, String>{};
    for (final field in session.fields) {
      var value = values[field.id] ?? '';
      if (field.obscureText && value.isEmpty && field.initialValue.isNotEmpty) {
        value = field.initialValue;
      }
      final maxLength =
          field.maxLength ?? RemoteTextInputService.absoluteMaxLength;
      if (value.length > maxLength) {
        return _error(
          request,
          400,
          '${field.title}不能超过 $maxLength 个字符',
        );
      }
      if (field.required && value.trim().isEmpty) {
        return _error(request, 400, '请填写${field.title}');
      }
      normalizedValues[field.id] = value;
    }
    session.submitValues(normalizedValues);
    if (_wantsJson(request)) {
      return _json(<String, dynamic>{'success': true});
    }
    return _html(_buildSuccessPage(session));
  }

  bool _wantsJson(Request request) {
    return request.url.queryParameters['format'] == 'json' ||
        (request.headers['accept'] ?? '').contains('application/json') ||
        (request.headers['content-type'] ?? '').contains('application/json');
  }

  Response _error(Request request, int statusCode, String message) {
    if (_wantsJson(request)) {
      return _json(
        <String, dynamic>{'success': false, 'message': message},
        statusCode: statusCode,
      );
    }
    return _html(
      _buildMessagePage('无法输入', message),
      statusCode: statusCode,
    );
  }

  Response _json(Map<String, dynamic> value, {int statusCode = 200}) {
    return Response(
      statusCode,
      body: json.encode(value),
      headers: const <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
        'Cache-Control': 'no-store',
      },
    );
  }

  Response _html(String value, {int statusCode = 200}) {
    return Response(
      statusCode,
      body: value,
      headers: const <String, String>{
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': 'no-store',
        'X-Content-Type-Options': 'nosniff',
        'Content-Security-Policy':
            "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'",
      },
    );
  }

  String _buildInputPage(Request request, RemoteTextInputSession session) {
    if (!session.isPending) {
      return _buildMessagePage('输入已完成', '此输入会话已经结束，可以关闭页面。');
    }
    final action = _escapeHtml(
      request.requestedUri.replace(query: null, fragment: null).toString(),
    );
    final title = _escapeHtml(session.title);
    final fields = <String>[];
    for (var index = 0; index < session.fields.length; index++) {
      final field = session.fields[index];
      final fieldTitle = _escapeHtml(field.title);
      final initial = _escapeHtml(field.obscureText ? '' : field.initialValue);
      final maxLength =
          field.maxLength ?? RemoteTextInputService.absoluteMaxLength;
      final required = field.required ? ' required' : '';
      final autofocus = index == 0 ? ' autofocus' : '';
      final preservedPassword =
          field.obscureText && field.initialValue.isNotEmpty
              ? '<span class="hint">留空则保持现有内容</span>'
              : '';
      final input = field.multiline
          ? '<textarea name="field_$index" maxlength="$maxLength"$required$autofocus>$initial</textarea>'
          : '<input name="field_$index" type="${field.obscureText ? 'password' : 'text'}" inputmode="${_inputMode(field.inputType)}" maxlength="$maxLength" value="$initial"$required$autofocus autocomplete="off">';
      fields.add(
        '<div class="field"><label>$fieldTitle${field.required ? ' *' : ''}</label>'
        '$input$preservedPassword</div>',
      );
    }
    return _pageShell(
      title,
      '<div class="badge">KEY ${_escapeHtml(session.displayKey)}</div>'
      '<p>在手机上完成${session.fields.length > 1 ? '这组' : ''}输入，提交后内容会自动回填到 Apple TV。</p>'
      '<form action="$action" method="post">'
      '${fields.join()}'
      '<button type="submit">发送到 Apple TV</button>'
      '</form>',
    );
  }

  String _buildSuccessPage(RemoteTextInputSession session) {
    return _buildMessagePage(
      '已发送',
      '内容已发送到 Apple TV，KEY ${session.displayKey} 已失效。',
    );
  }

  String _buildMessagePage(String title, String message) {
    return _pageShell(
      _escapeHtml(title),
      '<div class="result"><h1>${_escapeHtml(title)}</h1>'
      '<p>${_escapeHtml(message)}</p></div>',
    );
  }

  String _pageShell(String title, String body) {
    return '<!doctype html><html lang="zh-CN"><head>'
        '<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">'
        '<title>$title · NipaPlay</title><style>'
        ':root{color-scheme:light dark;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}'
        '*{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;background:#111;color:#f5f5f5;padding:20px}'
        'main{width:min(100%,560px);background:#1c1c1c;border:1px solid #383838;border-radius:22px;padding:26px;box-shadow:0 24px 70px #0008}'
        '.badge{display:inline-block;padding:7px 11px;border-radius:999px;background:#303030;font-weight:800;letter-spacing:.08em}'
        'p{color:#bdbdbd;line-height:1.6}.field{margin-top:20px}label{display:block;font-size:16px;font-weight:800;margin:0 0 8px}'
        'input,textarea{width:100%;font:inherit;font-size:18px;color:#fff;background:#111;border:2px solid #4a4a4a;border-radius:12px;padding:14px;outline:none}'
        'input:focus,textarea:focus{border-color:#ff2f78}textarea{min-height:150px;resize:vertical}'
        '.hint{display:block;color:#888;font-size:12px;margin-top:7px}'
        'button{width:100%;margin-top:18px;border:0;border-radius:12px;padding:15px;font:inherit;font-weight:800;color:#fff;background:#ff2f78}'
        '.result{text-align:center;padding:18px 0}h1{margin:0 0 12px}'
        '@media(prefers-color-scheme:light){body{background:#eee;color:#171717}main{background:#fff;border-color:#ddd;box-shadow:0 24px 70px #0002}p{color:#606060}input,textarea{color:#171717;background:#f5f5f5;border-color:#ccc}}'
        '</style></head><body><main>$body</main></body></html>';
  }

  String _inputMode(String inputType) {
    return switch (inputType) {
      'number' => 'decimal',
      'phone' => 'tel',
      'email' => 'email',
      'url' => 'url',
      _ => 'text',
    };
  }

  String _escapeHtml(String value) {
    return const HtmlEscape(HtmlEscapeMode.unknown).convert(value);
  }
}
