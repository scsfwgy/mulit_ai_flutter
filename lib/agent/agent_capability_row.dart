import 'package:flutter/cupertino.dart';
import 'package:mulit_ai_flutter/agent/agent_capability.dart';
import 'package:mulit_ai_flutter/agent/agent_runner.dart';
import 'package:mulit_ai_flutter/api/api_client.dart';
import 'package:mulit_ai_flutter/core/apple_purchases.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/core/storefront_policy.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

class AgentCapabilityRow extends StatefulWidget {
  const AgentCapabilityRow({super.key});
  @override
  State<AgentCapabilityRow> createState() => _AgentCapabilityRowState();
}

class _AgentCapabilityRowState extends State<AgentCapabilityRow> {
  AgentCapabilityCheck? _check;
  bool _checking = false;
  bool _loading = true;
  String? _result;
  String? _target;

  @override
  void initState() {
    super.initState();
    _loadTarget();
  }

  Future<({ProviderConfig provider, String model})?> _selection() async {
    final store = ChatStore.instance;
    final selection = await store.lastChatSelection();
    final providers = await store.providers();
    final provider =
        providers.where((p) => p.id == selection?.providerId).firstOrNull ??
        providers.firstOrNull;
    if (provider == null) return null;
    return (
      provider: provider,
      model: provider.id == selection?.providerId
          ? selection!.model
          : provider.model,
    );
  }

  Future<void> _loadTarget() async {
    try {
      final target = await _selection();
      if (mounted && target != null) {
        setState(
          () => _target = '${T(target.provider.name)} · ${target.model}',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _result = T('i18n.agent_probe_failed'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _test() async {
    if (_checking || AgentRunner.isBusy) return;
    setState(() {
      _checking = true;
      _result = null;
    });
    try {
      final store = ChatStore.instance;
      final target = await _selection();
      if (target == null) throw StateError('i18n.this_service_has_no_api');
      final provider = target.provider;
      final model = target.model;
      if (!mounted) return;
      setState(() => _target = '${T(provider.name)} · $model');
      if (!await ApplePurchases.instance.refresh()) {
        throw StateError('i18n.agent_access');
      }
      await StorefrontPolicy.instance.requireAllowed(
        provider.baseUrl,
        presetId: provider.presetId,
        model: model,
      );
      final key = await store.apiKey(provider.id);
      if (key == null || key.isEmpty) {
        throw StateError('i18n.this_service_has_no_api');
      }
      if (!mounted) return;
      _check = AgentCapabilityCheck(ModelApiClient(provider, key), model);
      final result = await _check!.run();
      if (mounted) {
        setState(
          () => _result = T(
            result == AgentCapabilityResult.passed
                ? 'i18n.agent_probe_passed'
                : 'i18n.agent_probe_inconclusive',
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _result = e.message);
    } on StateError catch (e) {
      if (mounted) setState(() => _result = T(e.message));
    } catch (_) {
      if (mounted) setState(() => _result = T('i18n.agent_probe_failed'));
    } finally {
      _check?.cancel();
      _check = null;
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  void dispose() {
    _check?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IosSection(
    footer: T('i18n.agent_probe_detail'),
    children: [
      IosRow(
        key: const Key('agent-capability-check'),
        title: T('i18n.agent_probe'),
        subtitle: [_target, _result].whereType<String>().join('\n').nullIfEmpty,
        trailing: _checking ? const CupertinoActivityIndicator() : null,
        onTap: _checking || _loading ? null : _test,
      ),
    ],
  );
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
