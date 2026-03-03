// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hebrew (`he`).
class AppLocalizationsHe extends AppLocalizations {
  AppLocalizationsHe([String locale = 'he']) : super(locale);

  @override
  String get hideUntilDue => 'עד ה';

  @override
  String get hideUntilDueTime => 'מועד הביצוע';

  @override
  String get hideUntilDayBefore => 'יום לפני מועד היעד';

  @override
  String get hideUntilWeekBefore => 'שבוע לפני מועד היעד';

  @override
  String get hideUntilSpecificDay => 'יום מועד';

  @override
  String get hideUntilSpecificDayTime => 'יום וזמן מועדים';

  @override
  String get hideUntilNone => 'אין תאריך התחלה';

  @override
  String get tomorrow => 'מחר';

  @override
  String get yesterday => 'אתמול';

  @override
  String get content => 'תוכן';

  @override
  String get title => 'תואר';

  @override
  String get save => 'שמור';

  @override
  String get clear => 'נקה';

  @override
  String get cancel => 'בטל';

  @override
  String get summary => 'תקציר';

  @override
  String get createNewTask => 'יצירת משימה חדשה';

  @override
  String get createNewNote => 'יצירת פתק חדש';

  @override
  String get search => 'חיפוש';

  @override
  String get filters => 'סינונים';

  @override
  String get later => 'מאוחר';

  @override
  String get priority => 'עדיפות';

  @override
  String get alarmTriggerNone => 'ללא';

  @override
  String get alarmTriggerStart => 'במועד ההתחלה';

  @override
  String get alarmTriggerEnd => 'במועד היעד';

  @override
  String get language => 'שפה';
}
