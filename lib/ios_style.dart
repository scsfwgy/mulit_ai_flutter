import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_preferences.dart';

abstract final class IosColors {
  static bool get _dark => AppPreferences.instance.dark;
  static Color get background =>
      _dark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
  static Color get surface =>
      _dark ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF);
  static Color get blue {
    final skin = AppPreferences.instance.skin;
    if (!_dark) return skin.accent;
    return switch (skin) {
      AppSkin.blue => const Color(0xFF0A84FF),
      AppSkin.teal => const Color(0xFF38C8B5),
      AppSkin.violet => const Color(0xFFAF8DF5),
    };
  }

  static Color get label =>
      _dark ? const Color(0xFFF5F5F7) : const Color(0xFF1C1C1E);
  static Color get secondary =>
      _dark ? const Color(0xFFAEAEB2) : const Color(0xFF8E8E93);
  static Color get separator =>
      _dark ? const Color(0xFF38383A) : const Color(0xFFE5E5EA);
  static Color get assistant =>
      _dark ? const Color(0xFF2C2C2E) : const Color(0xFFE9E9EB);
  static Color get destructive =>
      _dark ? const Color(0xFFFF453A) : const Color(0xFFFF3B30);
  static Color get onAccent =>
      _dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
  static Color get errorSurface =>
      _dark ? const Color(0xFF3D2223) : const Color(0xFFFFE9E8);
}

AppBar iosAppBar({
  required String title,
  Widget? titleWidget,
  Widget? leading,
  List<Widget>? actions,
}) => AppBar(
  title:
      titleWidget ??
      Text(tr(title), maxLines: 1, overflow: TextOverflow.ellipsis),
  centerTitle: true,
  leading: leading,
  leadingWidth: leading == null ? null : 90,
  actions: actions,
  backgroundColor: IosColors.surface,
  foregroundColor: IosColors.label,
  elevation: 0,
  scrolledUnderElevation: 0,
  toolbarHeight: 54,
  titleTextStyle: TextStyle(
    color: IosColors.label,
    fontSize: 17,
    fontWeight: FontWeight.w600,
  ),
  shape: Border(bottom: BorderSide(color: IosColors.separator, width: .5)),
);

class IosNavButton extends StatelessWidget {
  const IosNavButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.label,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? label;

  @override
  Widget build(BuildContext context) => CupertinoButton(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    minimumSize: const Size(44, 44),
    onPressed: onPressed,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 23, color: IosColors.blue),
        if (label != null) ...[
          const SizedBox(width: 3),
          Text(label!, style: TextStyle(color: IosColors.blue, fontSize: 16)),
        ],
      ],
    ),
  );
}

class IosSection extends StatelessWidget {
  const IosSection({
    super.key,
    this.title,
    this.footer,
    required this.children,
  });

  final String? title;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 21, 16, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 0, 8),
            child: Text(
              tr(title!).toUpperCase(),
              style: TextStyle(
                color: IosColors.secondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ColoredBox(
            color: IosColors.surface,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: EdgeInsets.only(left: 54),
                      child: Divider(
                        height: .5,
                        thickness: .5,
                        color: IosColors.separator,
                      ),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Text(
              tr(footer!),
              style: TextStyle(
                color: IosColors.secondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
      ],
    ),
  );
}

class IosRow extends StatelessWidget {
  const IosRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.chevron = true,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 58),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            if (leading != null) ...[
              SizedBox(width: 30, height: 30, child: Center(child: leading)),
              const SizedBox(width: 11),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tr(title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: IosColors.label, fontSize: 16),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      tr(subtitle!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: IosColors.secondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ?trailing,
            if (chevron)
              Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(
                  CupertinoIcons.chevron_right,
                  size: 15,
                  color: IosColors.secondary,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class IosPrimaryButton extends StatelessWidget {
  const IosPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 50,
    child: CupertinoButton.filled(
      borderRadius: BorderRadius.circular(12),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 19, color: IosColors.onAccent),
            const SizedBox(width: 8),
          ],
          Text(
            tr(label),
            style: TextStyle(
              color: IosColors.onAccent,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}
