import 'package:flutter/widgets.dart';

/// Keeps a growing chat at the latest message until the user scrolls away.
class ChatScrollController {
  ChatScrollController() {
    controller.addListener(_updateButton);
  }
  final controller = ScrollController();
  final showLatest = ValueNotifier(false);

  void _updateButton() {
    final visible =
        controller.hasClients && controller.position.extentAfter > 160;
    if (showLatest.value != visible) showLatest.value = visible;
  }

  bool _followingLatest = true;
  bool _dragging = false;
  int _scheduledScroll = 0;

  bool onScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;

    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _dragging = true;
      _followingLatest = false;
      _scheduledScroll++;
    } else if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _dragging = true;
      _followingLatest = false;
      _scheduledScroll++;
    } else if (notification is ScrollEndNotification && _dragging) {
      _dragging = false;
      _followingLatest = notification.metrics.extentAfter <= 20;
      if (_followingLatest) scrollToLatest();
    }
    return false;
  }

  void stopFollowing() {
    _dragging = false;
    _followingLatest = false;
    _scheduledScroll++;
  }

  void scrollToLatest({bool force = false}) {
    if (force) {
      showLatest.value = false;
      _dragging = false;
      _followingLatest = true;
    }
    if (!_followingLatest || _dragging) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) _updateButton();
      });
      return;
    }
    final request = ++_scheduledScroll;
    var remaining = 5;
    void settle(Duration _) {
      if (request != _scheduledScroll ||
          !_followingLatest ||
          _dragging ||
          !controller.hasClients) {
        return;
      }
      if (remaining < 5 && controller.position.extentAfter <= 1) {
        _updateButton();
        return;
      }
      controller.jumpTo(controller.position.maxScrollExtent);
      _updateButton();
      // Lazy lists may discover a much taller final message after the first jump.
      if (--remaining > 0) {
        WidgetsBinding.instance.addPostFrameCallback(settle);
        WidgetsBinding.instance.ensureVisualUpdate();
      }
    }

    WidgetsBinding.instance.addPostFrameCallback(settle);
  }

  bool _disposed = false;
  void dispose() {
    _disposed = true;
    _scheduledScroll++;
    controller.dispose();
    showLatest.dispose();
  }
}
