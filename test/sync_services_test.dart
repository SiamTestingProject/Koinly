import 'package:flutter_test/flutter_test.dart';
import 'package:koinly/sync_services.dart';

void main() {
  test('custom sync endpoint accepts only an HTTPS origin', () {
    expect(
      CloudSyncService.validateApiBaseUrl(' https://my-sync.example.com/ '),
      'https://my-sync.example.com',
    );
    expect(() => CloudSyncService.validateApiBaseUrl('http://my-sync.example.com'), throwsStateError);
    expect(() => CloudSyncService.validateApiBaseUrl('https://my-sync.example.com/v1'), throwsStateError);
  });
}
