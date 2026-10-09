/// A declaration/quote the user wants to read on a schedule.
///
/// Stage 1 only has personal quotes. In Stage 2, quotes from a Circle will
/// use the same shape (loaded from a hosted JSON file with stable ids).
class Quote {
   Quote({
    required this.id,
    required this.text,
    required this.notifBase,
    required this.createdAt,
    this.targetPerDay = 1,
    this.windowStartMin = 8 * 60,
    this.windowEndMin = 20 * 60,
    this.remindersOn = true,
    this.updatedAt,
    this.isCircle = false,
    this.circleId,
    this.unreadCount = 0,
    this.unreadCountFor = 0,
  });

  /// Stable id. Streaks and read history are keyed by this, so editing the
  /// text never resets a streak; deleting the quote does.
  final String id;

  String text;

  /// First notification id reserved for this quote (each quote may use up to
  /// [maxPerDay] consecutive ids).
  final int notifBase;

  final DateTime createdAt;

  /// The user's own daily target. "Full completion" is measured against this.
  int targetPerDay;

  /// Reminder window, in minutes from midnight.
  int windowStartMin;
  int windowEndMin;

  bool remindersOn;
  DateTime? updatedAt;   // null for quotes created before this change

  /// True for quotes that come from a hosted Circle file rather than the
  /// user's own personal list. Circle quotes can't be edited or deleted
  /// locally.
  final bool isCircle;
  final String? circleId;

  static const int maxPerDay = 24;
  int unreadCount;
  int unreadCountFor;

  /// Evenly spaced reminder times (minutes from midnight) across the window.
  /// One reminder a day fires at the window start.
  List<int> reminderMinutes() {
    final n = targetPerDay.clamp(1, maxPerDay).toInt();
    if (n == 1 || windowEndMin <= windowStartMin) return [windowStartMin];
    final step = (windowEndMin - windowStartMin) / (n - 1);
    return List<int>.generate(n, (i) => (windowStartMin + step * i).round());
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'notifBase': notifBase,
        'createdAt': createdAt.toIso8601String(),
        'targetPerDay': targetPerDay,
        'windowStartMin': windowStartMin,
        'windowEndMin': windowEndMin,
        'remindersOn': remindersOn,
        'unreadCount': unreadCount,
        'unreadCountFor': unreadCountFor,
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory Quote.fromJson(Map<String, dynamic> j) => Quote(
        id: j['id'] as String,
        text: j['text'] as String,
        notifBase: j['notifBase'] as int,
        createdAt: DateTime.parse(j['createdAt'] as String),
        targetPerDay: (j['targetPerDay'] as int?) ?? 1,
        windowStartMin: (j['windowStartMin'] as int?) ?? 8 * 60,
        windowEndMin: (j['windowEndMin'] as int?) ?? 20 * 60,
        remindersOn: (j['remindersOn'] as bool?) ?? true,
        unreadCount: (j['unreadCount'] as int?) ?? 0,
        unreadCountFor: (j['unreadCountFor'] as int?) ?? 0,
        updatedAt: j['updatedAt'] == null ? null : DateTime.parse(j['updatedAt'] as String)      
      );
}
