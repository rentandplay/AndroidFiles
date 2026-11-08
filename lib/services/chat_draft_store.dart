import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Local drafts are best effort. Only the server's saved message is 'Sent'.
/// The retry key is saved before transmission to recover an uncertain send.
class ChatDraftStore {
  ChatDraftStore(this.scope);
  final String scope;
  final _preferences = SharedPreferencesAsync();
  Future<void> _queue = Future.value();
  String get _key => 'rental_support_draft:$scope';
  Future<Map<String, dynamic>> load() async {
    final value = await _preferences.getString(_key);
    if (value == null) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(value) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> save(String text, Map<String, dynamic>? pending) {
    final value = jsonEncode({'text': text, 'pending': pending});
    return _queue = _queue
        .catchError((_) {})
        .then((_) => _preferences.setString(_key, value));
  }

  Future<void> clear() =>
      _queue = _queue.catchError((_) {}).then((_) => _preferences.remove(_key));
}
