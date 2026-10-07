import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/core/app_platform.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

enum ProviderQrScanMode { config, apiKey }

class ProviderQrScanner extends StatefulWidget {
  const ProviderQrScanner({super.key, this.mode = ProviderQrScanMode.config});

  final ProviderQrScanMode mode;

  @override
  State<ProviderQrScanner> createState() => _ProviderQrScannerState();
}

class _ProviderQrScannerState extends State<ProviderQrScanner>
    with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    formats: [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 500,
  );
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.hasCameraPermission) return;
    if (state == AppLifecycleState.resumed && !_processing) {
      unawaited(_startScanner());
    } else if (state == AppLifecycleState.inactive) {
      unawaited(_stopScanner());
    }
  }

  Future<void> _startScanner() async {
    try {
      await _controller.start();
    } catch (_) {
      // Camera and permission failures are shown by the scanner state.
    }
  }

  Future<void> _stopScanner() async {
    try {
      await _controller.stop();
    } catch (_) {
      // The controller may still be initializing during a permission dialog.
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing || !mounted) return;
    final raw = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .firstOrNull;
    if (raw == null) return;

    _processing = true;
    try {
      await _controller.stop();
      if (widget.mode == ProviderQrScanMode.apiKey) {
        final key = validateScannedApiKey(raw);
        if (mounted) Navigator.pop(context, key);
        return;
      }
      final value = ProviderConfig.fromQrCode(raw);
      await ChatStore.instance.saveProvider(value.config, apiKey: value.key);
      if (mounted) Navigator.pop(context, true);
    } on FormatException catch (error) {
      await _showError(error.message);
    } catch (_) {
      await _showError(T('i18n.import_failed_try_again'));
    }
  }

  Future<void> _showError(String message) async {
    if (!mounted) return;
    await showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(T('i18n.unable_to_import')),
        content: Text(T(message)),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: Text(T('i18n.scan_again')),
          ),
        ],
      ),
    );
    _processing = false;
    if (mounted &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      await _startScanner();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IosColors.background,
    appBar: iosAppBar(
      title: widget.mode == ProviderQrScanMode.apiKey ? T('i18n.scan_key') : T('i18n.scan_service'),
      leading: IosNavButton(
        icon: CupertinoIcons.back,
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Text(
              T(
                isDesktopApp
                    ? 'i18n.scanned_content_is_only_used'
                    : widget.mode == ProviderQrScanMode.apiKey
                    ? 'i18n.scan_a_qr_code_containing'
                    : 'i18n.scan_full_config_qr_hint',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: IosColors.secondary, fontSize: 14),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      controller: _controller,
                      onDetect: _onDetect,
                      placeholderBuilder: (_) =>
                          const ColoredBox(color: Colors.black),
                      errorBuilder: (_, _) =>
                          const ColoredBox(color: Colors.black),
                    ),
                    IgnorePointer(
                      child: Center(
                        child: Container(
                          width: 240,
                          height: 240,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 2),
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ),
                    ValueListenableBuilder<MobileScannerState>(
                      valueListenable: _controller,
                      builder: (context, state, _) {
                        if (state.error == null) return const SizedBox.shrink();
                        final denied =
                            state.error?.errorCode ==
                            MobileScannerErrorCode.permissionDenied;
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Text(
                              T(
                                denied
                                    ? 'i18n.allow_camera_access_in_system'
                                    : 'i18n.the_camera_is_unavailable_check',
                              ),
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 22),
            child: Text(
              T(
                widget.mode == ProviderQrScanMode.apiKey
                    ? 'i18n.check_the_scanned_key_before'
                    : 'i18n.the_qr_code_must_contain',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: IosColors.secondary, fontSize: 13),
            ),
          ),
        ],
      ),
    ),
  );
}
