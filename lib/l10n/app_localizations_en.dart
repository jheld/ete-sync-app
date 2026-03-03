// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get hideUntilDue => 'Due date';

  @override
  String get hideUntilDueTime => 'Due time';

  @override
  String get hideUntilDayBefore => 'Day Before Due';

  @override
  String get hideUntilWeekBefore => 'Week Before Due';

  @override
  String get hideUntilSpecificDay => 'Specific Day';

  @override
  String get hideUntilSpecificDayTime => 'Specific Day and Time';

  @override
  String get hideUntilNone => 'No start date';

  @override
  String get tomorrow => 'tomorrow';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get content => 'Content';

  @override
  String get title => 'Title';

  @override
  String get save => 'Save';

  @override
  String get clear => 'Clear';

  @override
  String get cancel => 'Cancel';

  @override
  String get summary => 'Summary';

  @override
  String get createNewTask => 'Create new task';

  @override
  String get createNewNote => 'Create new note';

  @override
  String get search => 'Search';

  @override
  String get filters => 'Filters';

  @override
  String get later => 'Later';

  @override
  String get priority => 'Priority';

  @override
  String get alarmTriggerNone => 'None';

  @override
  String get alarmTriggerStart => 'When started';

  @override
  String get alarmTriggerEnd => 'When due';

  @override
  String get language => 'Language';
}
