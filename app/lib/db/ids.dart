import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// UUIDv7 rather than autoincrement so ids stay collision-free if board sets
/// are ever merged across devices, and time-ordered so they index well.
String newId() => _uuid.v7();

int nowMs() => DateTime.now().millisecondsSinceEpoch;
