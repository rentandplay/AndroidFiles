import 'dart:convert';
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rent_and_play_app/services/mobile_api_service.dart';

class _FakeUser extends Fake implements User {
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async =>
      'firebase-id-token';
}

class _FakeAuth extends Fake implements FirebaseAuth {
  _FakeAuth(this.currentUser);

  @override
  final User? currentUser;
}

class _SseClient extends http.BaseClient {
  int requests = 0;
  String? authorization;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    authorization = request.headers['Authorization'];
    expect(request.url.path, endsWith('/api/rental-events'));
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(
        'retry: 15000\n\n'
        'event: ready\ndata: {"revision":3}\n\n'
        'event: rental.changed\ndata: {"revision":4,"rentalId":"rental-42"}\n\n',
      )),
      200,
      headers: {'content-type': 'text/event-stream; charset=utf-8'},
    );
  }
}

class _OpenSseClient extends http.BaseClient {
  final frames = StreamController<List<int>>();
  int requests = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    return http.StreamedResponse(frames.stream, 200,
        headers: {'content-type': 'text/event-stream'});
  }
}

void main() {
  test(
      'mobile parses authenticated rental SSE frames without opening a second API connection',
      () async {
    final client = _SseClient();
    final api = MobileApiService(auth: _FakeAuth(_FakeUser()), client: client);

    final events = await api.watchRentalEvents().take(2).toList();

    expect(client.requests, 1);
    expect(client.authorization, 'Bearer firebase-id-token');
    expect(events, [
      {'event': 'ready', 'revision': 3},
      {'event': 'rental.changed', 'revision': 4, 'rentalId': 'rental-42'},
    ]);
  });
  test(
      'the progress screen and notifications share a single live API connection',
      () async {
    final client = _OpenSseClient();
    final api = MobileApiService(auth: _FakeAuth(_FakeUser()), client: client);
    final progress = api.watchRentalEvents().take(2).toList();
    final notifications = api.watchRentalEvents().take(2).toList();
    await Future<void>.delayed(Duration.zero);
    client.frames.add(utf8.encode('event: ready\ndata: {"revision":1}\n\n'
        'event: rental.changed\ndata: {"revision":2,"rentalId":"r1"}\n\n'));
    expect(await progress, await notifications);
    expect(client.requests, 1);
    await client.frames.close();
  });
}
