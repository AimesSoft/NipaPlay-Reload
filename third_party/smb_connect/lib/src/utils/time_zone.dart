// typedef TimeZone = dynamic;

class TimeZone {
  final String zoneName;
  final Duration zoneOffset;
  TimeZone(this.zoneName, this.zoneOffset);

  static TimeZone getDefault() {
    final date = DateTime.now();
    return TimeZone(date.timeZoneName, date.timeZoneOffset);
  }

  bool inDaylightTime(DateTime date) {
    return 6 < date.hour && date.hour < 19;
  }
}
