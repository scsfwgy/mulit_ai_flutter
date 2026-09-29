class VoiceSendPreference {
  static const key = 'voice_auto_send';

  // Existing installations have no stored value; immediate sending is the default.
  static bool autoSend(String? value) => value != '0';
}
