import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_preferences.dart';
import 'apple_purchases.dart';
import 'ios_style.dart';

class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen({super.key, this.purchases});
  final ApplePurchases? purchases;
  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  ApplePurchases get store => widget.purchases ?? ApplePurchases.instance;
  @override
  void initState() {
    super.initState();
    store.start();
    store.refresh(products: true);
  }

  String get status {
    if (store.permanent) return tr('已永久解锁');
    if (!store.ready) return tr('正在检查购买记录');
    if (store.canUse && store.trialEnd != null) return tr('7 天试用中');
    if (store.error == 'clockUnavailable') return tr('等待联网验证试用');
    if (store.hadTrial) return tr('试用已结束');
    return tr('先试用，再决定');
  }

  String get feedback => tr(switch (store.error) {
    'clockUnavailable' => '请联网校准试用时间后重试。',
    'verificationFailed' => '购买记录验证失败，请联网重试或恢复购买。',
    'productsUnavailable' => '商店商品暂不可用，请稍后刷新。',
    'purchaseFailed' => '购买未完成，请重试。',
    'restoreFailed' => '恢复购买未完成，请联网重试。',
    _ => switch (store.outcome) {
      'pending' => '购买正在等待批准，批准后会自动解锁。',
      'alreadyClaimed' => '此 Apple 账户已领取过试用，恢复购买不会重新开始试用。',
      'nothingToRestore' => '没有可恢复的有效权益；已领取的试用不会重新开始。',
      'restored' => '购买记录已恢复。',
      _ => '',
    },
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) => Scaffold(
      appBar: iosAppBar(
        title: tr('试用与永久解锁'),
        leading: IosNavButton(
          icon: CupertinoIcons.back,
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Icon(CupertinoIcons.sparkles, color: IosColors.blue, size: 48),
            const SizedBox(height: 16),
            Text(
              status,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w600,
                color: IosColors.label,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              tr('一次买断，永久使用 iPhone、iPad 与配对 Apple Watch 功能。'),
              textAlign: TextAlign.center,
              style: TextStyle(color: IosColors.secondary, height: 1.5),
            ),
            if (store.trialEnd case final end?) ...[
              const SizedBox(height: 10),
              Text(
                '${tr('试用截止时间')}：${end.year}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')} ${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}',
                textAlign: TextAlign.center,
                style: TextStyle(color: IosColors.secondary),
              ),
            ],
            const SizedBox(height: 24),
            IosSection(
              children: [
                IosRow(
                  title: tr('文字、语音与联网搜索'),
                  subtitle: tr('自选模型、自备 API Key，保留本机聊天与配置。'),
                  chevron: false,
                ),
                IosRow(
                  title: tr('7 天全部功能试用'),
                  subtitle: tr('主动领取后开始，不自动续费、不自动扣款。'),
                  chevron: false,
                ),
                IosRow(
                  title: tr('第三方服务费用另计'),
                  subtitle: tr('买断价格不包含模型、语音或搜索服务的用量。'),
                  chevron: false,
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (!store.permanent) ...[
              if (!store.hadTrial)
                IosPrimaryButton(
                  label: tr('免费领取 7 天试用'),
                  onPressed: store.busy || !store.trialAvailable
                      ? null
                      : () => store.purchase(ApplePurchases.trialId),
                ),
              const SizedBox(height: 12),
              IosPrimaryButton(
                label: store.price == null
                    ? tr('永久解锁（价格加载中）')
                    : '${tr('永久解锁')} · ${store.price}',
                onPressed: store.busy || store.price == null
                    ? null
                    : () => store.purchase(ApplePurchases.permanentId),
              ),
            ],
            CupertinoButton(
              onPressed: store.busy ? null : store.restore,
              child: Text(tr('恢复购买')),
            ),
            CupertinoButton(
              onPressed: store.busy
                  ? null
                  : () => store.refresh(products: true),
              child: Text(tr('刷新商店')),
            ),
            if (store.busy) const CupertinoActivityIndicator(),
            if (feedback.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  feedback,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: IosColors.secondary, height: 1.5),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              tr('试用到期后，仍可阅读历史、管理配置及恢复购买。继续发起聊天、语音和搜索请求需要永久解锁。'),
              style: TextStyle(
                color: IosColors.secondary,
                fontSize: 13,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
