import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mulit_ai_flutter/core/apple_purchases.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

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
    if (store.permanent) return T('i18n.permanently_unlocked');
    if (!store.ready) return T('i18n.checking_purchases');
    if (store.canUse && store.trialEnd != null) {
      return T('i18n.7_day_trial_active');
    }
    if (store.error == 'clockUnavailable') {
      return T('i18n.connect_to_verify_your_trial');
    }
    if (store.hadTrial) return T('i18n.trial_has_ended');
    return T('i18n.try_it_then_decide');
  }

  String get feedback => T(switch (store.error) {
    'clockUnavailable' => 'i18n.connect_to_the_internet',
    'verificationFailed' => 'i18n.purchases_could_not_be_verified',
    'productsUnavailable' => 'i18n.store_products_are_unavailable_refresh',
    'purchaseFailed' => 'i18n.purchase_was_not_completed_try',
    'restoreFailed' => 'i18n.restore_was_not_completed_connect',
    'restoreTimedOut' => 'i18n.restore_timed_out',
    'queryTimedOut' => 'i18n.store_query_timed_out',
    _ => switch (store.outcome) {
      'success' => store.canUse ? 'i18n.purchase_access_unlocked' : '',
      'purchaseSyncPending' => 'i18n.purchase_access_sync_pending',
      'pending' => 'i18n.purchase_is_awaiting_approval_access',
      'alreadyClaimed' => 'i18n.this_apple_account_has_already',
      'nothingToRestore' => 'i18n.no_active_access_was_restored',
      'restored' => 'i18n.purchases_restored',
      _ => '',
    },
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) => Scaffold(
      appBar: iosAppBar(
        title: T('i18n.trial_permanent_unlock'),
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
              T('i18n.one_purchase_permanently_unlocks_iphone'),
              textAlign: TextAlign.center,
              style: TextStyle(color: IosColors.secondary, height: 1.5),
            ),
            if (feedback.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    feedback,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: IosColors.label, height: 1.5),
                  ),
                ),
              ),
            if (store.trialEnd case final end?) ...[
              const SizedBox(height: 10),
              Text(
                '${T('i18n.trial_ends')}：${end.year}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')} ${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}',
                textAlign: TextAlign.center,
                style: TextStyle(color: IosColors.secondary),
              ),
            ],
            const SizedBox(height: 24),
            IosSection(
              children: [
                IosRow(
                  title: T('i18n.text_voice_and_web_search'),
                  subtitle: T('i18n.choose_your_models_and_use'),
                  chevron: false,
                ),
                IosRow(
                  title: T('i18n.7_day_full_feature_trial'),
                  subtitle: T('i18n.starts_when_you_claim'),
                  chevron: false,
                ),
                IosRow(
                  title: T('i18n.third_party_usage_costs_extra'),
                  subtitle: T('i18n.the_unlock_price_does'),
                  chevron: false,
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (!store.permanent) ...[
              if (!store.hadTrial)
                IosPrimaryButton(
                  label: T('i18n.start_free_7_day_trial'),
                  onPressed: store.busy || !store.trialAvailable
                      ? null
                      : () => store.purchase(ApplePurchases.trialId),
                ),
              const SizedBox(height: 12),
              IosPrimaryButton(
                label: store.price == null
                    ? T('i18n.permanent_unlock_loading_price')
                    : '${T('i18n.permanent_unlock')} · ${store.price}',
                onPressed: store.busy || store.price == null
                    ? null
                    : () => store.purchase(ApplePurchases.permanentId),
              ),
            ],
            CupertinoButton(
              onPressed: store.busy ? null : store.restore,
              child: Text(T('i18n.restore_purchases')),
            ),
            CupertinoButton(
              onPressed: store.busy
                  ? null
                  : () => store.refresh(products: true),
              child: Text(T('i18n.refresh_store')),
            ),
            if (store.busy) const CupertinoActivityIndicator(),
            const SizedBox(height: 16),
            Text(
              T('i18n.after_the_trial_you_can'),
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
