const String defaultNipaPlayUserAgent = 'NipaPlay/1.0';

/// Removes control characters that are invalid in an HTTP header value.
String sanitizeHttpUserAgent(String value) =>
    value.replaceAll(RegExp(r'[\x00-\x08\x0A-\x1F\x7F]'), '').trim();
