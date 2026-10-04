import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Metadata only: never retain audio samples or transcript text in logs.
Map<String, Object?> voiceWavDiagnostics(
  Uint8List bytes, {
  bool includeLevels = true,
}) {
  final result = <String, Object?>{'file_bytes': bytes.length};
  String tag(int offset) =>
      String.fromCharCodes(bytes.sublist(offset, offset + 4));
  if (bytes.length < 12 || tag(0) != 'RIFF' || tag(8) != 'WAVE') {
    return {...result, 'container': 'not_riff_wave'};
  }
  result['container'] = 'RIFF/WAVE';
  final view = ByteData.sublistView(bytes);
  result['riff_declared_bytes'] = view.getUint32(4, Endian.little) + 8;
  final chunks = <String>[];
  int? format, bits, channels, rate, byteRate, dataOffset, dataLength;
  for (var offset = 12; offset + 8 <= bytes.length;) {
    final id = tag(offset);
    final length = view.getUint32(offset + 4, Endian.little);
    chunks.add(RegExp(r'^[\x20-\x7e]{4}$').hasMatch(id) ? id : '????');
    final start = offset + 8;
    if (id == 'fmt ' && length >= 16 && start + 16 <= bytes.length) {
      format = view.getUint16(start, Endian.little);
      channels = view.getUint16(start + 2, Endian.little);
      rate = view.getUint32(start + 4, Endian.little);
      byteRate = view.getUint32(start + 8, Endian.little);
      bits = view.getUint16(start + 14, Endian.little);
      result.addAll({
        'format_code': format,
        'sample_rate_hz': rate,
        'channels': channels,
        'bits_per_sample': bits,
        'byte_rate': byteRate,
      });
    }
    if (id == 'data') {
      dataOffset = start;
      dataLength = math.min(length, bytes.length - start);
      result.addAll({
        'data_declared_bytes': length,
        'data_actual_bytes': dataLength,
        'data_truncated': length > bytes.length - start,
      });
    }
    if (start + length > bytes.length) {
      result['truncated_chunk'] = true;
      break;
    }
    offset = start + length + (length.isOdd ? 1 : 0);
  }
  result['chunks'] = chunks;
  if (dataLength != null && byteRate != null && byteRate > 0) {
    result['duration_ms'] = (dataLength * 1000 / byteRate).round();
  }
  if (includeLevels &&
      format == 1 &&
      bits == 16 &&
      dataOffset != null &&
      dataLength != null) {
    var peak = 0, nonzero = 0;
    var squareSum = 0.0;
    final count = dataLength ~/ 2;
    for (var i = 0; i < count; i++) {
      final sample = view.getInt16(dataOffset + i * 2, Endian.little);
      peak = math.max(peak, sample.abs());
      if (sample != 0) nonzero++;
      squareSum += sample.toDouble() * sample;
    }
    result.addAll({
      'pcm16_peak': peak,
      'pcm16_nonzero_samples': nonzero,
      'pcm16_rms': count == 0
          ? 0
          : double.parse(math.sqrt(squareSum / count).toStringAsFixed(2)),
    });
  }
  return result;
}

/// Project only request schema and model options; never serialize raw payloads.
Map<String, Object?> voiceRequestDiagnostics(http.BaseRequest request) {
  final result = <String, Object?>{
    'method': request.method,
    'endpoint': request.url
        .replace(userInfo: '', query: '', fragment: '')
        .toString()
        .replaceFirst(RegExp(r'[?#]+$'), ''),
    'content_type': request is http.MultipartRequest
        ? 'multipart/form-data'
        : request.headers['Content-Type'],
    'request_bytes': request.contentLength,
    'follow_redirects': request.followRedirects,
    'auth_header': request.headers.containsKey('X-Api-Key')
        ? 'X-Api-Key'
        : 'Authorization: Bearer',
  };
  if (request is http.MultipartRequest) {
    result['model'] = request.fields['model'];
    result['file'] = [
      for (final file in request.files)
        {
          'field': file.field,
          'filename': file.filename,
          'content_type': file.contentType.toString(),
          'bytes': file.length,
        },
    ];
  } else if (request is http.Request) {
    try {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final messages = body['messages'];
      result['body'] = {
        if (body.containsKey('model')) 'model': body['model'],
        'stream': body['stream'] ?? '(omitted)',
        if (body['asr_options'] is Map)
          'asr_options': {'language': body['asr_options']['language']},
        if (messages is List)
          'messages': [
            for (final message in messages)
              if (message is Map)
                {
                  'role': message['role'],
                  'content': message['content'] is List
                      ? [
                          for (final part in message['content'])
                            if (part is Map)
                              {
                                'type': part['type'],
                                if (part['input_audio'] is Map)
                                  'input_audio': {
                                    'format': part['input_audio']['format'],
                                    'data': '<audio omitted>',
                                    'data_characters':
                                        (part['input_audio']['data'] as String?)
                                            ?.length,
                                    'data_url':
                                        (part['input_audio']['data'] as String?)
                                            ?.startsWith('data:') ??
                                        false,
                                  },
                              },
                        ]
                      : '<text omitted>',
                },
          ],
        if (body['audio'] is Map)
          'audio': {
            'format': body['audio']['format'] is String
                ? body['audio']['format']
                : null,
            'data': '<audio omitted>',
          },
        if (body['request'] is Map)
          'request': {'model_name': body['request']['model_name']},
        if (body['voice'] is String) 'voice': body['voice'],
        if (body['response_format'] is String)
          'response_format': body['response_format'],
      };
    } catch (_) {
      result['body'] = '<unavailable>';
    }
  }
  return result;
}
