/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:async';
import 'dart:collection';
import 'dart:ffi';

import 'package:media_kit/ffi/ffi.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as generated;
import 'package:synchronized/synchronized.dart';

/// {@template initializer_polling}
///
/// InitializerPolling
/// ------------------
/// Initializes [Pointer<mpv_handle>] & notifies about events through polling.
///
/// This implementation uses a Timer to periodically poll mpv_wait_event instead
/// of using NativeCallable for wakeup callbacks. This avoids the "Callback invoked
/// after it has been deleted" crash that occurs during Flutter hot restart when
/// using NativeCallable.
///
/// Trade-offs:
/// - Slightly higher latency (~16ms) compared to callback-based approach
/// - Slightly higher CPU usage due to polling
/// - But: No crash on hot restart, making it ideal for debug builds
///
/// {@endtemplate}
class InitializerPolling {
  /// Singleton instance.
  static InitializerPolling? _instance;

  /// {@macro initializer_polling}
  InitializerPolling._(this.mpv);

  /// {@macro initializer_polling}
  factory InitializerPolling(generated.MPV mpv) {
    _instance ??= InitializerPolling._(mpv);
    return _instance!;
  }

  /// Generated libmpv C API bindings.
  final generated.MPV mpv;

  /// Polling interval. 16ms ≈ 60fps, good balance between latency and CPU usage.
  static const _pollInterval = Duration(milliseconds: 16);

  /// Creates [Pointer<mpv_handle>].
  Future<Pointer<generated.mpv_handle>> create(
    Future<void> Function(Pointer<generated.mpv_event>) callback, {
    Map<String, String> options = const {},
  }) async {
    final ctx = mpv.mpv_create();
    for (final entry in options.entries) {
      final name = entry.key.toNativeUtf8();
      final value = entry.value.toNativeUtf8();
      mpv.mpv_set_option_string(ctx, name.cast(), value.cast());
      calloc.free(name);
      calloc.free(value);
    }
    mpv.mpv_initialize(ctx);

    // Store callback and create lock for this handle
    _locks[ctx.address] = Lock();
    _eventCallbacks[ctx.address] = callback;
    _disposed[ctx.address] = false;

    // Start polling timer for this handle
    _startPolling(ctx);

    return ctx;
  }

  /// Disposes [Pointer<mpv_handle>].
  void dispose(Pointer<generated.mpv_handle> ctx) {
    // Mark as disposed to stop polling
    _disposed[ctx.address] = true;

    // Stop and remove the timer
    _timers[ctx.address]?.cancel();
    _timers.remove(ctx.address);

    // Clean up other resources
    _locks.remove(ctx.address);
    _eventCallbacks.remove(ctx.address);
    _disposed.remove(ctx.address);
  }

  /// Starts the polling timer for a specific handle.
  void _startPolling(Pointer<generated.mpv_handle> ctx) {
    final timer = Timer.periodic(_pollInterval, (_) {
      _pollEvents(ctx);
    });
    _timers[ctx.address] = timer;
  }

  /// Polls and processes all pending events for a handle.
  void _pollEvents(Pointer<generated.mpv_handle> ctx) {
    // Check if disposed
    if (_disposed[ctx.address] == true) {
      return;
    }

    final lock = _locks[ctx.address];
    final callback = _eventCallbacks[ctx.address];

    if (lock == null || callback == null) {
      return;
    }

    // Use lock to ensure events are processed sequentially
    lock.synchronized(() async {
      // Double-check disposal inside lock
      if (_disposed[ctx.address] == true) {
        return;
      }

      // Drain all pending events
      while (true) {
        // Check disposal before each event
        if (_disposed[ctx.address] == true) {
          return;
        }

        // Non-blocking wait (timeout = 0)
        final event = mpv.mpv_wait_event(ctx, 0);
        if (event == nullptr) return;
        if (event.ref.event_id == generated.mpv_event_id.MPV_EVENT_NONE) return;

        try {
          await callback(event);
        } catch (exception, stacktrace) {
          print('media_kit: InitializerPolling: Error processing event');
          print(exception.toString());
          print(stacktrace.toString());
        }
      }
    });
  }

  final _locks = HashMap<int, Lock>();
  final _eventCallbacks = HashMap<int, EventCallback>();
  final _timers = HashMap<int, Timer>();
  final _disposed = HashMap<int, bool>();
}

typedef EventCallback = Future<void> Function(Pointer<generated.mpv_event>);
