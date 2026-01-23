/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit_video/media_kit_video_controls/media_kit_video_controls.dart'
    as media_kit_video_controls;
import 'package:media_kit_video/media_kit_video_controls/media_kit_video_controls.dart';
import 'package:media_kit_video/src/subtitle/subtitle_view.dart';
import 'package:media_kit_video/src/utils/dispose_safe_notifer.dart';
import 'package:media_kit_video/src/utils/wakelock.dart';
import 'package:media_kit_video/src/video/offscreen_behavior.dart';
import 'package:media_kit_video/src/video_controller/platform_video_controller.dart';
import 'package:media_kit_video/src/video_controller/video_controller.dart';
import 'package:media_kit_video/src/video_view_parameters.dart';

/// {@template video}
///
/// Video
/// -----
/// [Video] widget is used to display video output.
///
/// Use [VideoController] to initialize & handle the video rendering.
///
/// **Example:**
///
/// ```dart
/// class MyScreen extends StatefulWidget {
///   const MyScreen({Key? key}) : super(key: key);
///   @override
///   State<MyScreen> createState() => MyScreenState();
/// }
///
/// class MyScreenState extends State<MyScreen> {
///   late final player = Player();
///   late final controller = VideoController(player);
///
///   @override
///   void initState() {
///     super.initState();
///     player.open(Media('https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4'));
///   }
///
///   @override
///   void dispose() {
///     player.dispose();
///     super.dispose();
///   }
///
///   @override
///   Widget build(BuildContext context) {
///     return Scaffold(
///       body: Video(
///         controller: controller,
///       ),
///     );
///   }
/// }
/// ```
///
/// {@endtemplate}
class Video extends StatefulWidget {
  /// The [VideoController] reference to control this [Video] output.
  final VideoController controller;

  /// Width of this viewport.
  final double? width;

  /// Height of this viewport.
  final double? height;

  /// Fit of the viewport.
  final BoxFit fit;

  /// Background color to fill the video background.
  final Color fill;

  /// Alignment of the viewport.
  final Alignment alignment;

  /// Preferred aspect ratio of the viewport.
  final double? aspectRatio;

  /// Filter quality of the [Texture] widget displaying the video output.
  final FilterQuality filterQuality;

  /// Video controls builder.
  final VideoControlsBuilder? controls;

  /// Whether to acquire wake lock while playing the video.
  final bool wakelock;

  /// Whether to pause the video when application enters background mode.
  final bool pauseUponEnteringBackgroundMode;

  /// Whether to resume the video when application enters foreground mode.
  ///
  /// This attribute is only applicable if [pauseUponEnteringBackgroundMode] is `true`.
  ///
  final bool resumeUponEnteringForegroundMode;

  /// The configuration for subtitles e.g. [TextStyle] & padding etc.
  final SubtitleViewConfiguration subtitleViewConfiguration;

  /// The callback invoked when the [Video] enters fullscreen.
  final Future<void> Function() onEnterFullscreen;

  /// The callback invoked when the [Video] exits fullscreen.
  final Future<void> Function() onExitFullscreen;

  /// FocusNode for keyboard input.
  final FocusNode? focusNode;

  final Widget? thumbnail;

  /// Configuration for video behavior when scrolled offscreen.
  ///
  /// Use this to optimize performance when videos are in scrollable lists
  /// by pausing, suspending frame processing, or culling videos that are
  /// not visible.
  ///
  /// Example:
  /// ```dart
  /// Video(
  ///   controller: controller,
  ///   offscreenBehavior: OffscreenBehavior.powerSaving,
  /// )
  /// ```
  ///
  /// See [OffscreenBehavior] for available presets and customization options.
  final OffscreenBehavior offscreenBehavior;

  /// {@macro video}
  const Video({
    super.key,
    required this.controller,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.fill = const Color(0xFF000000),
    this.alignment = Alignment.center,
    this.aspectRatio,
    this.filterQuality = FilterQuality.low,
    this.controls = media_kit_video_controls.AdaptiveVideoControls,
    this.wakelock = true,
    this.pauseUponEnteringBackgroundMode = true,
    this.resumeUponEnteringForegroundMode = false,
    this.subtitleViewConfiguration = const SubtitleViewConfiguration(),
    this.onEnterFullscreen = defaultEnterNativeFullscreen,
    this.onExitFullscreen = defaultExitNativeFullscreen,
    this.focusNode,
    this.thumbnail,
    this.offscreenBehavior = const OffscreenBehavior(),
  });

  @override
  State<Video> createState() => VideoState();
}

class VideoState extends State<Video> with WidgetsBindingObserver {
  late final _contextNotifier = DisposeSafeNotifier<BuildContext?>(null);
  late ValueNotifier<VideoViewParameters> videoViewParametersNotifier;
  late bool _disposeNotifiers;
  final _subtitleViewKey = GlobalKey<SubtitleViewState>();
  final _wakelock = Wakelock();
  final _subscriptions = <StreamSubscription>[];
  late int? _width = widget.controller.player.state.width;
  late int? _height = widget.controller.player.state.height;
  late bool _visible = (_width ?? 0) > 0 && (_height ?? 0) > 0;
  // If autoplay is false then show thumbnail initially.
  late bool _showThumbnail = !widget.controller.player.state.playing;

  bool _pauseDueToPauseUponEnteringBackgroundMode = false;

  // Offscreen behavior state
  bool _isOffscreen = false;
  bool _pausedDueToOffscreen = false;
  bool _suspendedDueToOffscreen = false;
  Timer? _visibilityDebounceTimer;

  // Controls fade-in animation when restoring from culled state
  double _videoOpacity = 1.0;
  // Public API:
  bool isFullscreen() {
    return media_kit_video_controls.isFullscreen(_contextNotifier.value!);
  }

  Future<void> enterFullscreen() {
    return media_kit_video_controls.enterFullscreen(_contextNotifier.value!);
  }

  Future<void> exitFullscreen() {
    return media_kit_video_controls.exitFullscreen(_contextNotifier.value!);
  }

  Future<void> toggleFullscreen() {
    return media_kit_video_controls.toggleFullscreen(_contextNotifier.value!);
  }

  void setSubtitleViewPadding(
    EdgeInsets padding, {
    Duration duration = const Duration(milliseconds: 100),
  }) {
    return _subtitleViewKey.currentState?.setPadding(
      padding,
      duration: duration,
    );
  }

  /// Whether the thumbnail is currently being displayed.
  ///
  /// Returns `true` if:
  /// - A [Video.thumbnail] widget is provided, AND
  /// - The video is at position 0 (hasn't started playing yet)
  ///
  /// This can be used by video controls to hide loading indicators
  /// when a thumbnail is visible.
  bool get isShowingThumbnail => widget.thumbnail != null && _showThumbnail;

  /// Handles transition to offscreen state.
  void _handleOffscreen(double visibleFraction) {
    if (_isOffscreen) return; // Already offscreen
    _isOffscreen = true;

    final behavior = widget.offscreenBehavior;

    // Invoke callback first (before automatic actions)
    behavior.onOffscreen?.call(visibleFraction);

    // Pause if configured
    if (behavior.pauseWhenOffscreen) {
      if (widget.controller.player.state.playing) {
        _pausedDueToOffscreen = true;
        widget.controller.player.pause();
      }
    }

    // Suspend video output if configured
    if (behavior.suspensionMode != OffscreenSuspensionMode.none) {
      _suspendedDueToOffscreen = true;
      widget.controller.suspendVideoOutput(behavior.suspensionMode);
    }

    // Trigger rebuild for culling and reset opacity for fade-in on return
    if (behavior.cullWhenOffscreen) {
      _videoOpacity = 0.0; // Start invisible, will fade in when restored
      setState(() {});
    }
  }

  /// Handles transition to onscreen state.
  void _handleOnscreen(double visibleFraction) {
    if (!_isOffscreen) return; // Already onscreen
    _isOffscreen = false;

    final behavior = widget.offscreenBehavior;
    final wasCulled = behavior.cullWhenOffscreen;

    // Capture state before any async operations
    final wasSuspended = _suspendedDueToOffscreen;
    final wasPaused = _pausedDueToOffscreen;

    // Reset flags immediately
    _suspendedDueToOffscreen = false;
    _pausedDueToOffscreen = false;

    // If culling was enabled, we need to wait for the Texture to be re-mounted
    // before resuming video output. setState is async - rebuild happens next frame.
    if (wasCulled) {
      setState(() {});

      // Wait for the rebuild to complete before resuming
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;

        // Resume video output after Texture is mounted
        // MUST await to ensure video track is ready before playing
        if (wasSuspended) {
          await widget.controller.resumeVideoOutput();
        }

        // Resume playback after video output is restored
        if (behavior.resumeWhenOnscreen && wasPaused) {
          widget.controller.player.play();
        }

        // Trigger fade-in animation after video is ready
        if (mounted) {
          setState(() {
            _videoOpacity = 1.0;
          });
        }

        // Invoke callback last
        behavior.onOnscreen?.call(visibleFraction);
      });
    } else {
      // No culling - can resume immediately, but still need to await
      () async {
        if (wasSuspended) {
          await widget.controller.resumeVideoOutput();
        }

        if (behavior.resumeWhenOnscreen && wasPaused) {
          widget.controller.player.play();
        }

        behavior.onOnscreen?.call(visibleFraction);
      }();
    }
  }

  /// Called when visibility changes, with debouncing.
  void _onVisibilityChanged(double visibleFraction) {
    final behavior = widget.offscreenBehavior;
    if (!behavior.isEnabled) return;

    final isCurrentlyOffscreen =
        visibleFraction <= behavior.visibilityThreshold;

    // Skip if no change
    if (isCurrentlyOffscreen == _isOffscreen) return;

    // Cancel any pending debounce
    _visibilityDebounceTimer?.cancel();

    // Apply debouncing
    if (behavior.debounceDuration > Duration.zero) {
      _visibilityDebounceTimer = Timer(behavior.debounceDuration, () {
        if (isCurrentlyOffscreen) {
          _handleOffscreen(visibleFraction);
        } else {
          _handleOnscreen(visibleFraction);
        }
      });
    } else {
      // No debounce
      if (isCurrentlyOffscreen) {
        _handleOffscreen(visibleFraction);
      } else {
        _handleOnscreen(visibleFraction);
      }
    }
  }

  /// Checks the current visibility of this widget and triggers callbacks.
  void _checkVisibility() {
    if (!mounted) return;
    final behavior = widget.offscreenBehavior;
    if (!behavior.isEnabled) return;

    final renderObject = context.findRenderObject();
    if (renderObject == null || !renderObject.attached) return;

    final RenderBox? box = renderObject is RenderBox ? renderObject : null;
    if (box == null) return;

    // Get the viewport (scroll view) bounds
    final scrollableState = Scrollable.maybeOf(context);
    if (scrollableState == null) {
      // Not inside a scrollable - assume always visible
      _onVisibilityChanged(1.0);
      return;
    }

    final viewportRenderObject = scrollableState.context.findRenderObject();
    if (viewportRenderObject == null) return;

    try {
      // Get widget bounds in global coordinates
      final widgetSize = box.size;
      final widgetTopLeft = box.localToGlobal(Offset.zero);
      final widgetRect = widgetTopLeft & widgetSize;

      // Get viewport bounds in global coordinates
      final RenderBox viewportBox = viewportRenderObject as RenderBox;
      final viewportTopLeft = viewportBox.localToGlobal(Offset.zero);
      final viewportRect = viewportTopLeft & viewportBox.size;

      // Calculate intersection
      final intersection = widgetRect.intersect(viewportRect);

      // Calculate visible fraction
      final widgetArea = widgetRect.width * widgetRect.height;
      if (widgetArea <= 0) {
        _onVisibilityChanged(0.0);
        return;
      }

      final visibleArea = intersection.width > 0 && intersection.height > 0
          ? intersection.width * intersection.height
          : 0.0;

      final visibleFraction = visibleArea / widgetArea;
      _onVisibilityChanged(visibleFraction.clamp(0.0, 1.0));
    } catch (_) {
      // Ignore errors from detached render objects
    }
  }

  /// Handles scroll notifications to check visibility.
  bool _handleScrollNotification(ScrollNotification notification) {
    // Check visibility after each scroll update
    _checkVisibility();
    // Don't consume the notification
    return false;
  }

  void update({
    double? width,
    double? height,
    BoxFit? fit,
    Color? fill,
    Alignment? alignment,
    double? aspectRatio,
    FilterQuality? filterQuality,
    VideoControlsBuilder? controls,
    SubtitleViewConfiguration? subtitleViewConfiguration,
    FocusNode? focusNode,
  }) {
    videoViewParametersNotifier.value =
        videoViewParametersNotifier.value.copyWith(
      width: width,
      height: height,
      fit: fit,
      fill: fill,
      alignment: alignment,
      aspectRatio: aspectRatio,
      filterQuality: filterQuality,
      controls: controls,
      subtitleViewConfiguration: subtitleViewConfiguration,
      focusNode: focusNode,
    );
  }

  @override
  void didChangeDependencies() {
    videoViewParametersNotifier =
        media_kit_video_controls.VideoStateInheritedWidget.maybeOf(
              context,
            )?.videoViewParametersNotifier ??
            ValueNotifier<VideoViewParameters>(
              VideoViewParameters(
                width: widget.width,
                height: widget.height,
                fit: widget.fit,
                fill: widget.fill,
                alignment: widget.alignment,
                aspectRatio: widget.aspectRatio,
                filterQuality: widget.filterQuality,
                controls: widget.controls,
                subtitleViewConfiguration: widget.subtitleViewConfiguration,
                focusNode: widget.focusNode,
              ),
            );
    _disposeNotifiers =
        media_kit_video_controls.VideoStateInheritedWidget.maybeOf(
              context,
            )?.disposeNotifiers ??
            true;
    super.didChangeDependencies();
  }

  @override
  void didUpdateWidget(Video oldWidget) {
    super.didUpdateWidget(oldWidget);

    final currentParams = videoViewParametersNotifier.value;

    final newParams = currentParams.copyWith(
      width:
          widget.width != oldWidget.width ? widget.width : currentParams.width,
      height: widget.height != oldWidget.height
          ? widget.height
          : currentParams.height,
      fit: widget.fit != oldWidget.fit ? widget.fit : currentParams.fit,
      fill: widget.fill != oldWidget.fill ? widget.fill : currentParams.fill,
      alignment: widget.alignment != oldWidget.alignment
          ? widget.alignment
          : currentParams.alignment,
      aspectRatio: widget.aspectRatio != oldWidget.aspectRatio
          ? widget.aspectRatio
          : currentParams.aspectRatio,
      filterQuality: widget.filterQuality != oldWidget.filterQuality
          ? widget.filterQuality
          : currentParams.filterQuality,
      controls: widget.controls != oldWidget.controls
          ? widget.controls
          : currentParams.controls,
      subtitleViewConfiguration: widget.subtitleViewConfiguration !=
              oldWidget.subtitleViewConfiguration
          ? widget.subtitleViewConfiguration
          : currentParams.subtitleViewConfiguration,
      focusNode: widget.focusNode != oldWidget.focusNode
          ? widget.focusNode
          : currentParams.focusNode,
    );

    if (newParams != currentParams) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        videoViewParametersNotifier.value = newParams;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.pauseUponEnteringBackgroundMode) {
      if ([
        AppLifecycleState.paused,
        AppLifecycleState.detached,
      ].contains(state)) {
        if (widget.controller.player.state.playing) {
          _pauseDueToPauseUponEnteringBackgroundMode = true;
          widget.controller.player.pause();
        }
      } else {
        if (widget.resumeUponEnteringForegroundMode &&
            _pauseDueToPauseUponEnteringBackgroundMode) {
          _pauseDueToPauseUponEnteringBackgroundMode = false;
          widget.controller.player.play();
        }
      }
    }
    super.didChangeAppLifecycleState(state);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // --------------------------------------------------
    // Do not show the video frame until width & height are available.
    // Since [ValueNotifier<Rect?>] inside [VideoController] only gets updated by the render loop (i.e. it will not fire when video's width & height are not available etc.), it's important to handle this separately here.
    _subscriptions.addAll(
      [
        widget.controller.player.stream.width.listen(
          (value) {
            _width = value;
            final visible = (_width ?? 0) > 0 && (_height ?? 0) > 0;
            if (_visible != visible) {
              setState(() {
                _visible = visible;
              });
            }
          },
        ),
        widget.controller.player.stream.height.listen(
          (value) {
            _height = value;
            final visible = (_width ?? 0) > 0 && (_height ?? 0) > 0;
            if (_visible != visible) {
              setState(() {
                _visible = visible;
              });
            }
          },
        ),
        widget.controller.player.stream.playing.listen(
          (value) {
            if (value && !_showThumbnail) return;
            setState(() {
              // Using seconds instead of Duration.zero, because the position
              // sometimes reports milliseconds non zero even when autoplay is false.
              _showThumbnail =
                  widget.controller.player.state.position.inSeconds == 0;
            });
          },
        ),
        widget.controller.player.stream.position.listen(
          (value) {
            final playing = widget.controller.player.state.playing;
            if (playing && !_showThumbnail) return;

            setState(() {
              // Using seconds instead of Duration.zero, because the position
              // sometimes reports milliseconds non zero even when autoplay is false.
              _showThumbnail = value.inSeconds == 0;
            });
          },
        ),
      ],
    );
    // --------------------------------------------------
    if (widget.wakelock) {
      if (widget.controller.player.state.playing) {
        _wakelock.enable();
      }
      _subscriptions.add(
        widget.controller.player.stream.playing.listen(
          (value) {
            if (value) {
              _wakelock.enable();
            } else {
              _wakelock.disable();
            }
          },
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _visibilityDebounceTimer?.cancel();
    _wakelock.disable();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    if (_disposeNotifiers) {
      videoViewParametersNotifier.dispose();
      _contextNotifier.dispose();
      VideoStateInheritedWidgetContextNotifierState.fallback.remove(this);
    }

    super.dispose();
  }

  void refreshView() {}

  @override
  Widget build(BuildContext context) {
    // Schedule visibility check after build
    if (widget.offscreenBehavior.isEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkVisibility();
      });
    }

    Widget content = media_kit_video_controls.VideoStateInheritedWidget(
      state: this as dynamic,
      contextNotifier: _contextNotifier,
      videoViewParametersNotifier: videoViewParametersNotifier,
      child: ValueListenableBuilder<VideoViewParameters>(
        valueListenable: videoViewParametersNotifier,
        builder: (context, videoViewParameters, _) {
          return Container(
            clipBehavior: Clip.none,
            width: videoViewParameters.width,
            height: videoViewParameters.height,
            color: videoViewParameters.fill,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRect(
                  child: FittedBox(
                    fit: videoViewParameters.fit,
                    alignment: videoViewParameters.alignment,
                    child: _buildVideoTexture(videoViewParameters),
                  ),
                ),
                if (widget.thumbnail != null)
                  Positioned.fill(
                    child: AnimatedOpacity(
                      opacity: _showThumbnail ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 150),
                      child: IgnorePointer(
                        ignoring: !_showThumbnail,
                        child: widget.thumbnail!,
                      ),
                    ),
                  ),
                if (videoViewParameters.subtitleViewConfiguration.visible &&
                    !(widget.controller.player.platform?.configuration.libass ??
                        false))
                  Positioned.fill(
                    child: SubtitleView(
                      controller: widget.controller,
                      key: _subtitleViewKey,
                      configuration:
                          videoViewParameters.subtitleViewConfiguration,
                    ),
                  ),
                if (videoViewParameters.controls != null)
                  Positioned.fill(
                    child: videoViewParameters.controls!.call(this),
                  ),
              ],
            ),
          );
        },
      ),
    );

    // Wrap with scroll notification listener if offscreen behavior is enabled
    if (widget.offscreenBehavior.isEnabled) {
      content = NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: content,
      );
    }

    return content;
  }

  /// Builds the video texture widget, with culling support.
  Widget _buildVideoTexture(VideoViewParameters videoViewParameters) {
    // If culling is enabled and we're offscreen, return a placeholder
    if (widget.offscreenBehavior.cullWhenOffscreen && _isOffscreen) {
      return ValueListenableBuilder<PlatformVideoController?>(
        valueListenable: widget.controller.notifier,
        builder: (context, notifier, _) {
          if (notifier == null) return const SizedBox.shrink();
          return ValueListenableBuilder<Rect?>(
            valueListenable: notifier.rect,
            builder: (context, rect, _) {
              if (rect == null || !_visible) return const SizedBox.shrink();
              // Return a colored placeholder of the same size
              return SizedBox(
                width: videoViewParameters.aspectRatio == null
                    ? rect.width
                    : rect.height * videoViewParameters.aspectRatio!,
                height: rect.height,
                child: Container(color: videoViewParameters.fill),
              );
            },
          );
        },
      );
    }

    // Normal video texture rendering with fade-in support
    final textureWidget = ValueListenableBuilder<PlatformVideoController?>(
      valueListenable: widget.controller.notifier,
      builder: (context, notifier, _) => notifier == null
          ? const SizedBox.shrink()
          : ValueListenableBuilder<int?>(
              valueListenable: notifier.id,
              builder: (context, id, _) {
                return ValueListenableBuilder<Rect?>(
                  valueListenable: notifier.rect,
                  builder: (context, rect, _) {
                    if (id != null && rect != null && _visible) {
                      return SizedBox(
                        // Apply aspect ratio if provided.
                        width: videoViewParameters.aspectRatio == null
                            ? rect.width
                            : rect.height * videoViewParameters.aspectRatio!,
                        height: rect.height,
                        child: Stack(
                          children: [
                            const SizedBox(),
                            Positioned.fill(
                              child: Texture(
                                textureId: id,
                                filterQuality:
                                    videoViewParameters.filterQuality,
                              ),
                            ),
                            // Keep the |Texture| hidden before the first frame renders. In native implementation, if no default frame size is passed (through VideoController), a starting 1 pixel sized texture/surface is created to initialize the render context & check for H/W support.
                            // This is then resized based on the video dimensions & accordingly texture ID, texture, EGLDisplay, EGLSurface etc. (depending upon platform) are also changed. Just don't show that 1 pixel texture to the UI.
                            // NOTE: Unmounting |Texture| causes the |MarkTextureFrameAvailable| to not do anything on GNU/Linux.
                            if (rect.width <= 1.0 && rect.height <= 1.0)
                              Positioned.fill(
                                child: Container(
                                  color: videoViewParameters.fill,
                                ),
                              ),
                          ],
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                );
              },
            ),
    );

    // Wrap with AnimatedOpacity for smooth fade-in when restoring from culled state
    if (widget.offscreenBehavior.cullWhenOffscreen) {
      return AnimatedOpacity(
        opacity: _videoOpacity,
        duration: const Duration(milliseconds: 150),
        child: textureWidget,
      );
    }

    return textureWidget;
  }
}

typedef VideoControlsBuilder = Widget Function(VideoState state);

// --------------------------------------------------

/// Makes the native window enter fullscreen.
Future<void> defaultEnterNativeFullscreen() async {
  try {
    if (Platform.isAndroid || Platform.isIOS) {
      await Future.wait(
        [
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.immersiveSticky,
            overlays: [],
          ),
          SystemChrome.setPreferredOrientations(
            [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ],
          ),
        ],
      );
    } else if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      await const MethodChannel('com.alexmercerind/media_kit_video')
          .invokeMethod(
        'Utils.EnterNativeFullscreen',
      );
    }
  } catch (exception, stacktrace) {
    debugPrint(exception.toString());
    debugPrint(stacktrace.toString());
  }
}

/// Makes the native window exit fullscreen.
Future<void> defaultExitNativeFullscreen() async {
  try {
    if (Platform.isAndroid || Platform.isIOS) {
      await Future.wait(
        [
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.manual,
            overlays: SystemUiOverlay.values,
          ),
          SystemChrome.setPreferredOrientations(
            [],
          ),
        ],
      );
    } else if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      await const MethodChannel('com.alexmercerind/media_kit_video')
          .invokeMethod(
        'Utils.ExitNativeFullscreen',
      );
    }
  } catch (exception, stacktrace) {
    debugPrint(exception.toString());
    debugPrint(stacktrace.toString());
  }
}
// --------------------------------------------------
