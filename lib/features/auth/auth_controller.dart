import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum AuthStatus { loading, unauthenticated, authenticated }

/// Listens to Supabase Auth state and exposes it to the UI,
/// plus the user's profile row (role drives which shell is shown).
class AuthController extends ChangeNotifier {
  AuthController() {
    final client = Supabase.instance.client;
    _session = client.auth.currentSession;
    _status = _session == null
        ? AuthStatus.unauthenticated
        : AuthStatus.authenticated;

    _authSub = client.auth.onAuthStateChange.listen(_onAuthState);

    if (_session != null) {
      _loadProfile();
    } else {
      notifyListeners();
    }
  }

  final SupabaseClient _client = Supabase.instance.client;
  late final StreamSubscription<AuthState> _authSub;

  Session? _session;
  AuthStatus _status = AuthStatus.loading;
  Map<String, dynamic>? _profile;
  bool _profileLoading = false;

  AuthStatus get status => _status;
  Session? get session => _session;
  User? get user => _session?.user;
  Map<String, dynamic>? get profile => _profile;

  String? get role => _profile?['role'] as String?;
  bool get isRider => role == 'rider';
  bool get isAdminOrDirector =>
      role == 'admin' || role == 'director';
  String? get branchId => _profile?['branch_id'] as String?;
  bool get profileLoading => _profileLoading;

  void _onAuthState(AuthState data) {
    _session = data.session;
    _status = data.session == null
        ? AuthStatus.unauthenticated
        : AuthStatus.authenticated;
    if (data.session != null) {
      _loadProfile();
    } else {
      _profile = null;
      _profileLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadProfile() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    _profileLoading = true;
    notifyListeners();
    try {
      final profile = await _client
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();
      _profile = profile;
    } catch (_) {
      _profile = null;
    }
    _profileLoading = false;
    notifyListeners();
  }

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
