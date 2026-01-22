/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:ffi';
import 'dart:async';
import 'dart:isolate';
import 'dart:collection';

import 'package:media_kit/ffi/ffi.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as generated;
import 'package:media_kit/src/player/native/core/native_library.dart';
import 'package:media_kit/src/values.dart';

/// {@template initializer_isolate}
///
/// InitializerIsolate
/// ------------------
/// Initializes [Pointer<mpv_handle>] & notifies about events through the supplied callback.
///
/// {@endtemplate}
class InitializerIsolate {
  /// Singleton instance.
  static InitializerIsolate? _instance;

  /// {@macro initializer_isolate}
  InitializerIsolate._(this.libmpv);

  /// {@macro initializer_isolate}
  factory InitializerIsolate() {
    _instance ??= InitializerIsolate._(NativeLibrary.path);
    return _instance!;
  }

  /// Resolved libmpv dynamic library.
  final String libmpv;

  /// Creates [Pointer<mpv_handle>].
  Future<Pointer<generated.mpv_handle>> create(
    Future<void> Function(Pointer<generated.mpv_event>) callback, {
    Map<String, String> options = const {},
  }) async {
    final completer = Completer();
    final receiver = ReceivePort();
    late SendPort port;
    late Pointer<generated.mpv_handle> handle;
    final isolate = await Isolate.spawn(
      _mainloop,
      receiver.sendPort,
    );
    receiver.listen(
      (message) async {
        if (!completer.isCompleted && message is SendPort) {
          port = message;
          port.send(options);
          port.send(libmpv);
        } else if (!completer.isCompleted && message is int) {
          handle = Pointer.fromAddress(message);
          // Intialiation complete.
          completer.complete();
        }
        // Forward events to the supplied callback.
        else if (message != null) {
          Pointer<generated.mpv_event> event = Pointer.fromAddress(message);
          try {
            await callback(event);
          } catch (exception, stacktrace) {
            print(exception.toString());
            print(stacktrace.toString());
          }
          port.send(true);
        } else {
          receiver.close();
        }
      },
    );
    // Awaiting the retrieval of [Pointer<mpv_handle>].
    await completer.future;

    // Save the references.
    _ports[handle.address] = port;
    _isolates[handle.address] = isolate;

    return handle;
  }

  /// Disposes [Pointer<mpv_handle>].
  void dispose(generated.MPV mpv, Pointer<generated.mpv_handle> handle) {
    final port = _ports[handle.address];
    final isolate = _isolates[handle.address];
    if (port != null && isolate != null) {
      port.send(null);

      _ports.remove(handle.address);
      _isolates.remove(handle.address);

      mpv.mpv_wakeup(handle);

      Future.delayed(const Duration(seconds: 2), () {
        isolate.kill(priority: Isolate.immediate);
      });
    }
  }

  static void _mainloop(SendPort port) async {
    Completer completer = Completer();

    final receiver = ReceivePort();
    port.send(receiver.sendPort);

    late Map<String, String> options;
    late generated.MPV mpv;

    bool disposed = false;

    Pointer<generated.mpv_handle>? handle;

    receiver.listen(
      (message) {
        if (message is Map<String, String>) {
          options = message;
        } else if (message is String) {
          mpv = generated.MPV(DynamicLibrary.open(message));
          completer.complete();
        } else if (message is bool) {
          completer.complete();
        } else if (message == null) {
          if (handle != null) {
            disposed = true;
            completer.complete();
          }
        }
      },
    );

    // Add timeout to initialization wait to handle hot restart during init.
    // If main isolate dies before sending options/libmpv, this prevents zombie.
    try {
      await completer.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      print(
          'media_kit: InitializerIsolate: Init timeout, main isolate likely dead');
      port.send(null);
      receiver.close();
      Isolate.exit();
    }

    handle ??= mpv.mpv_create();

    for (final entry in options.entries) {
      final name = entry.key.toNativeUtf8();
      final value = entry.value.toNativeUtf8();
      mpv.mpv_set_option_string(handle, name.cast(), value.cast());
      calloc.free(name);
      calloc.free(value);
    }

    mpv.mpv_initialize(handle);
    port.send(handle.address);

    // Track consecutive timeouts to detect dead main isolate.
    // Using 10 second timeout to avoid false positives during heavy processing.
    // After 2 consecutive timeouts (20 seconds), assume main isolate is dead.
    int consecutiveTimeouts = 0;
    const maxConsecutiveTimeouts = 2;

    while (!disposed) {
      completer = Completer();
      final event = mpv.mpv_wait_event(handle, kReleaseMode ? -1 : 0.1);
      if (disposed) {
        break;
      }
      if (event.ref.event_id != generated.mpv_event_id.MPV_EVENT_NONE) {
        port.send(event.address);
        // Add timeout to detect dead main isolate (e.g., after hot restart).
        // If the main isolate is dead, no one will complete this future.
        try {
          await completer.future.timeout(const Duration(seconds: 10));
          consecutiveTimeouts = 0; // Reset on successful response
        } on TimeoutException {
          consecutiveTimeouts++;
          if (consecutiveTimeouts >= maxConsecutiveTimeouts) {
            // Main isolate is likely dead (hot restart), exit gracefully
            print(
                'media_kit: InitializerIsolate: Main isolate unresponsive, exiting');
            disposed = true;
            break;
          }
        }
      } else {
        await Future.delayed(Duration.zero);
      }
    }

    // Clean up mpv resources before exiting
    if (handle != null) {
      // Send quit command to stop mpv processing
      final cmd = 'quit'.toNativeUtf8();
      try {
        mpv.mpv_command_string(handle, cmd.cast());
      } finally {
        calloc.free(cmd);
      }
      // Note: We don't call mpv_terminate_destroy here because:
      // - NativeReferenceHolder tracks the handle
      // - It will be cleaned up on next hot restart or normal dispose
    }

    port.send(null);
    receiver.close();
    // Exit the isolate explicitly
    Isolate.exit();
  }

  final _ports = HashMap<int, SendPort>();
  final _isolates = HashMap<int, Isolate>();
}
