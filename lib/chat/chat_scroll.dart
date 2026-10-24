import 'package:flutter/widgets.dart';

/// Keeps a growing chat at the latest message until the user scrolls away.
class ChatScrollController {
  final controller = ScrollController();

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
      _dragging = false;
      _followingLatest = true;
    }
    if (!_followingLatest || _dragging) return;
    final request = ++_scheduledScroll;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (request != _scheduledScroll ||
          !_followingLatest ||
          _dragging ||
          !controller.hasClients) {
        return;
      }
      controller.jumpTo(controller.position.maxScrollExtent);
    });
  }

  void dispose() => controller.dispose();
}
