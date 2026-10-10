import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:mulit_ai_flutter/core/storefront_policy.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

const apiKeyTutorialUrl = 'https://www.tools24.uk/app/ai-link/help/apikey';
const mimoApiKeyUrl = 'https://platform.xiaomimimo.com/';
const doubaoVoiceApiKeyUrl =
    'https://console.volcengine.com/speech/new/setting/apikeys?projectName=default';

const textApiKeyUrls = <String, String>{
  'openai': 'https://platform.openai.com/api-keys',
  'claude': 'https://platform.claude.com/',
  'gemini': 'https://aistudio.google.com/app/apikey',
  'deepseek': 'https://platform.deepseek.com/api_keys',
  'glm': 'https://bigmodel.cn/',
  'qwen': 'https://bailian.console.aliyun.com/',
  'doubao': 'https://console.volcengine.com/ark/',
  'baidu': 'https://console.bce.baidu.com/qianfan/overview',
  'hunyuan': 'https://console.cloud.tencent.com/tokenhub',
  'moonshot': 'https://platform.kimi.com/console/api-keys',
  'minimax': 'https://platform.minimaxi.com/',
  'siliconflow': 'https://cloud.siliconflow.cn/',
  'openrouter': 'https://openrouter.ai/settings/keys',
  'grok': 'https://console.x.ai/',
  'groq': 'https://console.groq.com/keys',
  'mistral': 'https://console.mistral.ai/',
  'perplexity': 'https://www.perplexity.ai/account/api',
  'together': 'https://api.together.ai/',
  'fireworks': 'https://app.fireworks.ai/',
};

/// Compatibility describes the protocol, not who operates a custom endpoint.
/// Only known official hosts get a provider-specific credential link.
String? textApiKeyUrlForEndpoint(String endpoint) {
  if (StorefrontPolicy.instance.blocks(endpoint)) return null;
  final uri = Uri.tryParse(endpoint.trim());
  if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
    return null;
  }
  for (final preset in providerPresets) {
    if (Uri.parse(preset.baseUrl).host == uri.host) {
      return textApiKeyUrls[preset.id];
    }
  }
  return null;
}

String? voiceApiKeyUrlForEndpoint(VoiceProtocol protocol, String endpoint) {
  if (StorefrontPolicy.instance.blocks(endpoint)) return null;
  final uri = Uri.tryParse(endpoint.trim());
  if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
    return null;
  }
  return switch (protocol) {
    VoiceProtocol.mimo when uri.host == 'api.xiaomimimo.com' => mimoApiKeyUrl,
    VoiceProtocol.doubao when uri.host == 'openspeech.bytedance.com' =>
      doubaoVoiceApiKeyUrl,
    VoiceProtocol.openAi => textApiKeyUrlForEndpoint(endpoint),
    _ => null,
  };
}

Future<void> openApiKeyHelp(BuildContext context, String url) async {
  if (StorefrontPolicy.instance.blocks(url)) return;
  try {
    if (await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
      return;
    }
  } catch (_) {
    // A browser is optional; leave the public URL available to copy.
  }
  if (!context.mounted) return;
  await showCupertinoDialog<void>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: Text(T('i18n.could_not_open_a_browser')),
      content: Text(url),
      actions: [
        CupertinoDialogAction(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: url));
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          },
          child: Text(T('i18n.copy_url')),
        ),
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(T('i18n.ok')),
        ),
      ],
    ),
  );
}

class ApiKeyHelpRow extends StatelessWidget {
  const ApiKeyHelpRow({
    super.key,
    required this.url,
    this.title = 'i18n.api_key_guide',
    this.enabled = true,
  });

  final String url;
  final String title;
  final bool enabled;

  @override
  Widget build(BuildContext context) => IosRow(
    title: T(title),
    subtitle: url.replaceFirst('https://', ''),
    leading: Icon(CupertinoIcons.link, color: IosColors.blue, size: 22),
    onTap: enabled ? () => openApiKeyHelp(context, url) : null,
  );
}

class ApiKeyHelpSection extends StatelessWidget {
  const ApiKeyHelpSection({
    super.key,
    required this.category,
    this.officialUrl,
    this.enabled = true,
  });

  final String category;
  final String? officialUrl;
  final bool enabled;

  @override
  Widget build(BuildContext context) => IosSection(
    title: T('i18n.get_api_key'),
    children: [
      if (officialUrl != null)
        ApiKeyHelpRow(title: T('i18n.get_an_api_key'), url: officialUrl!, enabled: enabled),
      ApiKeyHelpRow(url: '$apiKeyTutorialUrl#$category', enabled: enabled),
    ],
  );
}
