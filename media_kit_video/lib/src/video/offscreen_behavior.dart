/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.

/// Defines how video frame processing should be suspended when offscreen.
enum OffscreenSuspensionMode {
  /// No suspension - video continues processing frames when offscreen.
  /// This is the default behavior for backward compatibility.
  none,

  /// Disable video output by setting mpv's `vo=null`.
  /// - Stops frame rendering callbacks
  /// - Video decoding may continue (lower CPU savings)
  /// - Quick resume with minimal stutter
  ///
  /// **Note:** On Android, this mode is automatically converted to
  /// [disableDecoding] because the Android video output cannot be safely
  /// detached and reattached.
  disableOutput,

  /// Disable video track by setting mpv's `vid=no`.
  /// - Stops video decoding entirely (maximum CPU savings)
  /// - Audio continues playing if not paused
  /// - Resume may cause brief frame skip
  disableDecoding,
}

/// Configuration for video behavior when scrolled offscreen.
///
/// This allows fine-grained control over how the video player behaves
/// when the [Video] widget is not visible in the viewport.
///
/// Example usage:
/// ```dart
/// Video(
///   controller: controller,
///   offscreenBehavior: OffscreenBehavior(
///     pauseWhenOffscreen: true,
///     resumeWhenOnscreen: true,
///     cullWhenOffscreen: true,
///     suspensionMode: OffscreenSuspensionMode.disableOutput,
///   ),
/// )
/// ```
class OffscreenBehavior {
  /// Whether to pause playback when the video scrolls offscreen.
  ///
  /// When `true`, the player will automatically pause when the video
  /// widget's visibility drops below [visibilityThreshold].
  ///
  /// Defaults to `false` for backward compatibility.
  final bool pauseWhenOffscreen;

  /// Whether to resume playback when the video scrolls back into view.
  ///
  /// Only applies if [pauseWhenOffscreen] is `true` and the video was
  /// playing before it went offscreen.
  ///
  /// Defaults to `false` for backward compatibility.
  final bool resumeWhenOnscreen;

  /// Whether to remove the [Texture] widget from the render tree when offscreen.
  ///
  /// When `true`, the video texture is replaced with an empty container,
  /// which can reduce GPU memory usage and improve scrolling performance.
  ///
  /// Defaults to `false`.
  final bool cullWhenOffscreen;

  /// How to suspend video frame processing when offscreen.
  ///
  /// This controls whether and how mpv stops processing video frames
  /// when the video is not visible.
  ///
  /// **Platform notes:**
  /// - On **Android**, [OffscreenSuspensionMode.disableOutput] is automatically
  ///   converted to [OffscreenSuspensionMode.disableDecoding] because Android's
  ///   video output is tied to a surface that cannot be safely detached and
  ///   reattached. This still provides significant power savings.
  /// - On other platforms (iOS, macOS, Windows, Linux), both modes work as expected.
  ///
  /// Defaults to [OffscreenSuspensionMode.none].
  final OffscreenSuspensionMode suspensionMode;

  /// Visibility threshold (0.0-1.0) below which the video is considered offscreen.
  ///
  /// - `0.0` means the video must be completely invisible
  /// - `0.5` means less than 50% visible triggers offscreen behavior
  /// - `1.0` means any partial occlusion triggers offscreen behavior
  ///
  /// Defaults to `0.0` (completely offscreen).
  final double visibilityThreshold;

  /// Debounce duration for visibility changes.
  ///
  /// This prevents rapid pause/resume cycles when scrolling quickly.
  /// Set to [Duration.zero] to disable debouncing.
  ///
  /// Defaults to 150 milliseconds.
  final Duration debounceDuration;

  /// Callback invoked when the video transitions to offscreen state.
  ///
  /// This is called after debouncing and before any automatic actions
  /// (pause, suspend, cull) are applied. Can be used for custom handling
  /// like analytics, logging, or additional cleanup.
  ///
  /// The callback receives the current visibility fraction (0.0 - 1.0).
  ///
  /// Example:
  /// ```dart
  /// OffscreenBehavior(
  ///   pauseWhenOffscreen: true,
  ///   onOffscreen: (visibleFraction) {
  ///     print('Video went offscreen with $visibleFraction visible');
  ///     analytics.track('video_offscreen');
  ///   },
  /// )
  /// ```
  final void Function(double visibleFraction)? onOffscreen;

  /// Callback invoked when the video transitions to onscreen state.
  ///
  /// This is called after debouncing and after the widget is restored
  /// (uncull, resume output, resume playback). Can be used for custom
  /// handling like analytics, logging, or triggering additional behavior.
  ///
  /// The callback receives the current visibility fraction (0.0 - 1.0).
  ///
  /// Example:
  /// ```dart
  /// OffscreenBehavior(
  ///   pauseWhenOffscreen: true,
  ///   resumeWhenOnscreen: true,
  ///   onOnscreen: (visibleFraction) {
  ///     print('Video came onscreen with $visibleFraction visible');
  ///     analytics.track('video_onscreen');
  ///   },
  /// )
  /// ```
  final void Function(double visibleFraction)? onOnscreen;

  /// Creates an [OffscreenBehavior] configuration.
  const OffscreenBehavior({
    this.pauseWhenOffscreen = false,
    this.resumeWhenOnscreen = false,
    this.cullWhenOffscreen = false,
    this.suspensionMode = OffscreenSuspensionMode.none,
    this.visibilityThreshold = 0.0,
    this.debounceDuration = const Duration(milliseconds: 150),
    this.onOffscreen,
    this.onOnscreen,
  }) : assert(
          visibilityThreshold >= 0.0 && visibilityThreshold <= 1.0,
          'visibilityThreshold must be between 0.0 and 1.0',
        );

  /// Preset: No offscreen behavior (default, backward compatible).
  static const OffscreenBehavior none = OffscreenBehavior();

  /// Preset: Pause when offscreen, resume when visible.
  static const OffscreenBehavior pauseAndResume = OffscreenBehavior(
    pauseWhenOffscreen: true,
    resumeWhenOnscreen: true,
  );

  /// Preset: Aggressive power saving - pause, suspend rendering, and cull.
  static const OffscreenBehavior powerSaving = OffscreenBehavior(
    pauseWhenOffscreen: true,
    resumeWhenOnscreen: true,
    cullWhenOffscreen: true,
    suspensionMode: OffscreenSuspensionMode.disableOutput,
  );

  /// Preset: Maximum power saving - stops video decoding entirely.
  static const OffscreenBehavior maxPowerSaving = OffscreenBehavior(
    pauseWhenOffscreen: true,
    resumeWhenOnscreen: true,
    cullWhenOffscreen: true,
    suspensionMode: OffscreenSuspensionMode.disableDecoding,
  );

  /// Whether any offscreen behavior is enabled.
  ///
  /// Returns true if any automatic behavior is enabled (pause, cull, suspend)
  /// OR if any callback is registered (onOffscreen, onOnscreen).
  bool get isEnabled =>
      pauseWhenOffscreen ||
      cullWhenOffscreen ||
      suspensionMode != OffscreenSuspensionMode.none ||
      onOffscreen != null ||
      onOnscreen != null;

  /// Creates a copy with the given fields replaced.
  ///
  /// Note: Callbacks ([onOffscreen], [onOnscreen]) are copied by reference.
  /// To clear a callback, you cannot use copyWith - create a new instance instead.
  OffscreenBehavior copyWith({
    bool? pauseWhenOffscreen,
    bool? resumeWhenOnscreen,
    bool? cullWhenOffscreen,
    OffscreenSuspensionMode? suspensionMode,
    double? visibilityThreshold,
    Duration? debounceDuration,
    void Function(double visibleFraction)? onOffscreen,
    void Function(double visibleFraction)? onOnscreen,
  }) {
    return OffscreenBehavior(
      pauseWhenOffscreen: pauseWhenOffscreen ?? this.pauseWhenOffscreen,
      resumeWhenOnscreen: resumeWhenOnscreen ?? this.resumeWhenOnscreen,
      cullWhenOffscreen: cullWhenOffscreen ?? this.cullWhenOffscreen,
      suspensionMode: suspensionMode ?? this.suspensionMode,
      visibilityThreshold: visibilityThreshold ?? this.visibilityThreshold,
      debounceDuration: debounceDuration ?? this.debounceDuration,
      onOffscreen: onOffscreen ?? this.onOffscreen,
      onOnscreen: onOnscreen ?? this.onOnscreen,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is OffscreenBehavior &&
        other.pauseWhenOffscreen == pauseWhenOffscreen &&
        other.resumeWhenOnscreen == resumeWhenOnscreen &&
        other.cullWhenOffscreen == cullWhenOffscreen &&
        other.suspensionMode == suspensionMode &&
        other.visibilityThreshold == visibilityThreshold &&
        other.debounceDuration == debounceDuration &&
        other.onOffscreen == onOffscreen &&
        other.onOnscreen == onOnscreen;
  }

  @override
  int get hashCode {
    return Object.hash(
      pauseWhenOffscreen,
      resumeWhenOnscreen,
      cullWhenOffscreen,
      suspensionMode,
      visibilityThreshold,
      debounceDuration,
      onOffscreen,
      onOnscreen,
    );
  }

  @override
  String toString() {
    return 'OffscreenBehavior('
        'pauseWhenOffscreen: $pauseWhenOffscreen, '
        'resumeWhenOnscreen: $resumeWhenOnscreen, '
        'cullWhenOffscreen: $cullWhenOffscreen, '
        'suspensionMode: $suspensionMode, '
        'visibilityThreshold: $visibilityThreshold, '
        'debounceDuration: $debounceDuration, '
        'onOffscreen: ${onOffscreen != null ? "Function" : "null"}, '
        'onOnscreen: ${onOnscreen != null ? "Function" : "null"})';
  }
}
