import 'package:enough_icalendar/enough_icalendar.dart';

Property? iCalendarCustomParser(String name, String definition) {
  switch (name) {
    case "X-LIC-ERROR":
    case "X-LIC-ERRORTYPE":
    case "X-EVOLUTION-ALARM-UID":
    case "X-TZINFO":
      return Property(definition, ValueType.text);
    case "ACKNOWLEDGED":
    case "X-MOZ-SNOOZE-TIME":
    case "X-MOZ-LASTACK":
      return Property(definition, ValueType.dateTime);
    case "X-MOZ-GENERATION":
    case "X-APPLE-SORT-ORDER":
      return Property(definition, ValueType.integer);
    case "X-VOBJ-FLOATINGTIME-ALLOWED":
      return Property(definition, ValueType.boolean);
    default:
      if (name.startsWith("X-MOZ-SNOOZE-TIME-")) {
        return Property(definition, ValueType.dateTime);
      }
      return null;
  }
}
