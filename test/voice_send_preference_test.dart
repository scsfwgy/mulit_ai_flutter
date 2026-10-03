import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/voice_send_preference.dart';

void main() {
  test('legacy watch requests send after transcription by default', () {
    expect(VoiceSendPreference.autoSend(null), isTrue);
    expect(VoiceSendPreference.autoSend('1'), isTrue);
    expect(VoiceSendPreference.autoSend('0'), isFalse);
  });
}
