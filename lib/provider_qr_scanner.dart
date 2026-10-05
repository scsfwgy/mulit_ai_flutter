import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'data.dart';
import 'app_preferences.dart';
import 'app_platform.dart';
import 'ios_style.dart';

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
      await _showError('导入失败，请重试');
    }
  }

  Future<void> _showError(String message) async {
    if (!mounted) return;
    await showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(tr('无法导入')),
        content: Text(tr(message)),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('继续扫码')),
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
      title: widget.mode == ProviderQrScanMode.apiKey ? '扫码填写密钥' : '扫码导入服务',
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
              tr(
                isDesktopApp
                    ? '识别内容仅用于填写或导入配置。密钥保存在本机安全存储中。'
                    : widget.mode == ProviderQrScanMode.apiKey
                    ? '扫描仅包含 API Key 字符串的二维码，识别后自动填入。'
                    : '扫描包含完整服务配置 JSON 的二维码，识别成功后自动导入。',
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
                              tr(
                                denied
                                    ? '请在系统设置中允许相机权限后返回重试'
                                    : '相机暂不可用，请检查设备相机后重试',
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
              tr(
                widget.mode == ProviderQrScanMode.apiKey
                    ? '扫码后请检查密钥并保存服务。密钥保存在设备安全存储中；选作手表服务时会经配对通道同步，Wear OS 加密保存，Apple Watch 使用钥匙串。'
                    : '二维码需包含 name、protocol、baseUrl、model、apiKey。\n密钥保存在设备安全存储中；选作手表服务时会经配对通道同步，Wear OS 加密保存，Apple Watch 使用钥匙串。',
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
