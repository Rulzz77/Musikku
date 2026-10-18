/// Invalidates asynchronous account-scoped work when the active account
/// changes or a user starts an account-changing action (login/logout).
///
/// Each request captures the returned generation and verifies both generation
/// and normalized email before applying results to UI/cache state.
class AccountRequestGuard {
  String _activeIdentity = '';
  int _generation = 0;

  int observe(String? email) {
    final identity = _normalize(email);
    if (identity != _activeIdentity) {
      _activeIdentity = identity;
      _generation++;
    }
    return _generation;
  }

  int invalidate() {
    _activeIdentity = '';
    return ++_generation;
  }

  bool isCurrent({
    required int generation,
    required String expectedEmail,
    required String? activeEmail,
    bool isMounted = true,
  }) {
    if (!isMounted || generation != _generation) return false;
    final expected = _normalize(expectedEmail);
    final active = _normalize(activeEmail);
    return expected.isNotEmpty &&
        _activeIdentity == expected &&
        active == expected;
  }

  String _normalize(String? email) => (email ?? '').trim().toLowerCase();
}
