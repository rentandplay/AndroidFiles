import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:rent_and_play_app/screens/shared/support_chat_screen.dart';
import 'package:rent_and_play_app/services/chat_draft_store.dart';
import 'package:rent_and_play_app/services/mobile_api_service.dart';

class ChatApi extends Fake implements MobileApiService {
  @override
  String get signedInUserId => 'customer';
  final requests = <Map<String, dynamic>>[];
  bool failOnce = true;
  final thread = <String, dynamic>{
    'id': 'thread',
    'subject': 'Console inquiry',
    'rental_code': 'RN-001',
    'customer_name': 'Customer',
    'status': 'OPEN',
    'staff_read_seq': 0
  };
  @override
  Future<Map<String, dynamic>> adminRequest(String path,
      {String method = 'GET',
      Map<String, dynamic>? body,
      bool forceRefresh = false}) async {
    if (path.endsWith('/read') || path.endsWith('/typing')) return {'thread': thread, 'ok': true};
    if (method == 'POST') {
      requests.add(Map.from(body!));
      if (failOnce) {
        failOnce = false;
        throw const MobileApiException('Connection interrupted',
            statusCode: 503);
      }
      return {
        'thread': thread,
        'message': {
          'id': 'saved',
          'seq': 1,
          'sender_role': 'CUSTOMER',
          'sender_name': 'Customer',
          'text': body['text'],
          'created_at': '2026-11-07T12:00:00Z'
        }
      };
    }
    return {
      'thread': thread,
      'messages': <Map<String, dynamic>>[],
      'next_cursor': null,
      'has_more': false
    };
  }
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  test('local draft survives store recreation and stays scoped to the account',
      () async {
    final operation = {'text': 'Availability?', 'requestKey': 'a' * 32};
    await ChatDraftStore('alice:thread').save('Availability?', operation);
    expect((await ChatDraftStore('alice:thread').load())['pending'], operation);
    expect(await ChatDraftStore('bob:thread').load(), isEmpty);
    await ChatDraftStore('alice:thread').clear();
    expect(await ChatDraftStore('alice:thread').load(), isEmpty);
  });
  testWidgets(
      'an interrupted send can be retried after leaving and reopening with its original key',
      (tester) async {
    final api = ChatApi();
    Widget screen() =>
        MaterialApp(home: SupportChatScreen(threadId: 'thread', api: api));
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Is the console available?');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(api.requests, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(api.requests, hasLength(2));
    expect(api.requests[0]['requestKey'], api.requests[1]['requestKey']);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
