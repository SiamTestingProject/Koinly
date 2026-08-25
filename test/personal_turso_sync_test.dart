import 'package:flutter_test/flutter_test.dart';

import 'package:koinly/models.dart';
import 'package:koinly/sync_services.dart';

void main() {
  test('personal Turso sync accepts a user Worker URL', () {
    expect(userSyncDatabaseProviders, contains(SyncDatabaseProvider.turso));
    expect(
      CloudSyncService.resolveApiBaseUrl(
          'https://personal-sync.example.workers.dev/'),
      'https://personal-sync.example.workers.dev',
    );
  });
}
