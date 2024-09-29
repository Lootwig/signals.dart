import 'dart:async';

extension ObjectUtils<T> on T? {
  R? safeCast<R>() {
    final that = this;
    if (that is R) return that;
    return null;
  }

  R? convert<R>(R Function(T)? cb) {
    if (this case final T nonNull) return cb?.call(nonNull);
    return null;
  }
}

extension FutureObjectUtils<T> on FutureOr<T?> {
  FutureOr<R?>? asyncCast<R>() async => (await this).safeCast<R>();

  FutureOr<Out?>? convertAsync<Out>(
    FutureOr<Out> Function(T input)? convert,
  ) async {
    if (await this case final T nonNull when convert != null) {
      final result = await convert(nonNull);
      return result.safeCast<Out>();
    }
    return null;
  }
}
