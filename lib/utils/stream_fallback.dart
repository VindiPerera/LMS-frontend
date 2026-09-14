import 'dart:async';

/// `Stream.handleError((e) => fallbackValue)` does NOT do what it looks like
/// it does: `handleError`'s callback is a `void Function(Object, [StackTrace])`,
/// so returning a value from it is simply discarded — the error is swallowed,
/// but no replacement event is ever pushed downstream. A `StreamBuilder`
/// listening to a stream built that way sees neither data nor an error once
/// the underlying query fails, so it sits in `ConnectionState.waiting`
/// forever (e.g. a permanently-spinning chat list when the Firestore query
/// backing it hits a `failed-precondition` for a missing composite index).
///
/// This extension actually emits [fallback] in place of a suppressed error.
extension StreamFallback<T> on Stream<T> {
  Stream<T> withFallback(T Function() fallback, {void Function(Object error)? onError}) {
    return transform(
      StreamTransformer<T, T>.fromHandlers(
        handleError: (error, stackTrace, sink) {
          onError?.call(error);
          sink.add(fallback());
        },
      ),
    );
  }
}
