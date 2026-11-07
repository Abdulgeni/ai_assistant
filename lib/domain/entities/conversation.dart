import 'package:ai_assistant/domain/entities/value_object.dart';

/// A chat thread. [title] is empty until derived from the first user message.
final class Conversation extends ValueObject {
  const Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  Conversation copyWith({String? title, DateTime? updatedAt}) => Conversation(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  List<Object?> get props => <Object?>[id, title, createdAt, updatedAt];

  // The title is derived from user text; never print it.
  @override
  String toString() => 'Conversation(id: $id)';
}
