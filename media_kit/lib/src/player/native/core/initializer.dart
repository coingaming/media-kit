/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:ffi';

import 'package:media_kit/generated/libmpv/bindings.dart' as generated;
import 'package:media_kit/src/player/native/core/execmem_restriction.dart';
import 'package:media_kit/src/player/native/core/initializer_isolate.dart';
import 'package:media_kit/src/player/native/core/initializer_native_callable.dart';
import 'package:media_kit/src/player/native/core/initializer_polling.dart';
import 'package:media_kit/src/values.dart';

/// {@template initializer}
///
/// Initializer
/// -----------
/// Initializes [Pointer<mpv_handle>] & notifies about events through the supplied callback.
///
/// Uses different implementations based on platform and build mode:
/// - **Release/Profile mode**: Uses [InitializerNativeCallable] for efficient callback-based event handling
/// - **Debug mode**: Uses [InitializerPolling] to avoid NativeCallable crash on hot restart
/// - **Execmem restricted platforms**: Uses [InitializerIsolate] (polling in separate isolate)
///
/// The debug mode polling approach avoids the "Callback invoked after it has been deleted"
/// crash that occurs when Flutter hot restart destroys the Dart isolate while libmpv's
/// background threads still hold references to the NativeCallable trampoline.
///
/// {@endtemplate}
class Initializer {
  /// Singleton instance.
  static Initializer? _instance;

  /// {@macro initializer}
  Initializer._(this.mpv);

  /// {@macro initializer}
  factory Initializer(generated.MPV mpv) {
    _instance ??= Initializer._(mpv);
    return _instance!;
  }

  /// Generated libmpv C API bindings.
  final generated.MPV mpv;

  /// Creates [Pointer<mpv_handle>].
  Future<Pointer<generated.mpv_handle>> create(
    Future<void> Function(Pointer<generated.mpv_event>) callback, {
    Map<String, String> options = const {},
  }) async {
    if (isExecmemRestricted) {
      // Execmem restricted platforms (e.g., iOS) use isolate-based polling
      return InitializerIsolate().create(callback, options: options);
    } else if (kDebugMode) {
      // Debug mode: Use polling to avoid NativeCallable crash on hot restart
      return InitializerPolling(mpv).create(callback, options: options);
    } else {
      // Release/Profile mode: Use efficient NativeCallable
      return InitializerNativeCallable(mpv).create(callback, options: options);
    }
  }

  /// Disposes [Pointer<mpv_handle>].
  void dispose(Pointer<generated.mpv_handle> ctx) {
    if (isExecmemRestricted) {
      InitializerIsolate().dispose(mpv, ctx);
    } else if (kDebugMode) {
      InitializerPolling(mpv).dispose(ctx);
    } else {
      InitializerNativeCallable(mpv).dispose(ctx);
    }
  }
}
