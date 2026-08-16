import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum AuthStatus { loading, unauthenticated, authenticated }

/// Listens to Supabase Auth state and exposes it to the UI.
class AuthController extends ChangeNotifier {
  AuthController() {
    final client = Supabase.instance.client;
    _session = client.auth.currentSession;
    _status = _session == null
        ? AuthStatus.unauthenticated
        : AuthStatus.authenticated;

    _authSub = client.auth.onAuthStateChange.listen((data) {
      _session = data.session;
      _status = data.session == null
          ? AuthStatus.unauthenticated
          : AuthStatus.authenticated;
      notifyListeners();
    });
  }

  final SupabaseClient _client = Supabase.instance.client;
  late final StreamSubscription<AuthState> _authSub;

  Session? _session;
  AuthStatus _status = AuthStatus.loading;

  AuthStatus get status => _status;
  Session? get session => _session;
  User? get user => _session?.user;

  Future<void> signIn({required String email, required String password}) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() => _client.auth.signOut();

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }
}
