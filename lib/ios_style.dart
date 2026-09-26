import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

abstract final class IosColors {
  static const background = Color(0xFFF2F2F7);
  static const surface = Color(0xFFFFFFFF);
  static const blue = Color(0xFF007AFF);
  static const label = Color(0xFF1C1C1E);
  static const secondary = Color(0xFF8E8E93);
  static const separator = Color(0xFFE5E5EA);
  static const assistant = Color(0xFFE9E9EB);
  static const destructive = Color(0xFFFF3B30);
}

AppBar iosAppBar({
  required String title,
  Widget? leading,
  List<Widget>? actions,
}) => AppBar(
  title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
  centerTitle: true,
  leading: leading,
  leadingWidth: leading == null ? null : 90,
  actions: actions,
  backgroundColor: IosColors.surface,
  foregroundColor: IosColors.label,
  elevation: 0,
  scrolledUnderElevation: 0,
  toolbarHeight: 54,
  titleTextStyle: const TextStyle(
    color: IosColors.label,
    fontSize: 17,
    fontWeight: FontWeight.w600,
  ),
  shape: const Border(
    bottom: BorderSide(color: IosColors.separator, width: .5),
  ),
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
          Text(
            label!,
            style: const TextStyle(color: IosColors.blue, fontSize: 16),
          ),
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
              title!.toUpperCase(),
              style: const TextStyle(
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
                    const Padding(
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
              footer!,
              style: const TextStyle(
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
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: IosColors.label,
                      fontSize: 16,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
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
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(
                  CupertinoIcons.chevron_right,
                  size: 15,
                  color: Color(0xFFC7C7CC),
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
          if (icon != null) ...[Icon(icon, size: 19), const SizedBox(width: 8)],
          Text(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}
