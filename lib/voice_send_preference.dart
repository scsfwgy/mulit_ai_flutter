class VoiceSendPreference {
  static const key = 'voice_auto_send';

  // Legacy watch requests can omit this value; default to immediate sending.
  static bool autoSend(String? value) => value != '0';
}
