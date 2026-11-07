/// Base class giving immutable domain types value equality without any
/// external package (the domain layer imports only `dart:` core libraries).
///
/// Subclasses list the fields that define equality in [props]. Lists are
/// compared element-wise.
///
/// NOTE: the default [toString] prints every prop. Any subclass that carries
/// user text (chat content, transcripts) MUST override it.
abstract class ValueObject {
  const ValueObject();

  List<Object?> get props;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ValueObject &&
          runtimeType == other.runtimeType &&
          _deepEquals(props, other.props));

  @override
  int get hashCode => Object.hash(runtimeType, _deepHash(props));

  @override
  String toString() => '$runtimeType(${props.join(', ')})';
}

bool _deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is List<Object?> && b is List<Object?>) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

int _deepHash(Object? value) {
  if (value is List<Object?>) return Object.hashAll(value.map(_deepHash));
  return value.hashCode;
}
