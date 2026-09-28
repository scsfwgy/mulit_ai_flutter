import 'package:flutter/cupertino.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'data.dart';
import 'ios_style.dart';

class ProviderBadge extends StatelessWidget {
  const ProviderBadge({
    super.key,
    required this.name,
    this.presetId,
    this.size = 22,
  });

  final String name;
  final String? presetId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final preset = providerPresets
        .where((item) => item.id == presetId)
        .firstOrNull;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: preset == null
            ? IosColors.blue
            : preset.id == 'moonshot'
            ? const Color(0xFF161B2B)
            : IosColors.surface,
        border: Border.all(color: IosColors.separator, width: .5),
        borderRadius: BorderRadius.circular(size * .24),
      ),
      child: preset == null
          ? Text(
              name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: TextStyle(
                color: IosColors.onAccent,
                fontSize: size * .55,
                fontWeight: FontWeight.w700,
              ),
            )
          : Padding(
              padding: EdgeInsets.all(size * .14),
              child: SvgPicture.asset(preset.iconAsset),
            ),
    );
  }
}
