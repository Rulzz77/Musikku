import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/services/account_request_guard.dart';

void main() {
  group('AccountRequestGuard', () {
    test('accepts a request while its account remains active', () {
      final guard = AccountRequestGuard();
      final generation = guard.observe('music@example.com');

      expect(
        guard.isCurrent(
          generation: generation,
          expectedEmail: 'music@example.com',
          activeEmail: 'music@example.com',
        ),
        isTrue,
      );
    });

    test('rejects results after active account changes', () {
      final guard = AccountRequestGuard();
      final accountAGeneration = guard.observe('a@example.com');
      final accountBGeneration = guard.observe('b@example.com');

      expect(
        guard.isCurrent(
          generation: accountAGeneration,
          expectedEmail: 'a@example.com',
          activeEmail: 'b@example.com',
        ),
        isFalse,
      );
      expect(
        guard.isCurrent(
          generation: accountBGeneration,
          expectedEmail: 'B@example.com',
          activeEmail: ' b@example.com ',
        ),
        isTrue,
      );
    });

    test('invalidating an account makes pending work stale', () {
      final guard = AccountRequestGuard();
      final generation = guard.observe('music@example.com');
      guard.invalidate();

      expect(
        guard.isCurrent(
          generation: generation,
          expectedEmail: 'music@example.com',
          activeEmail: 'music@example.com',
        ),
        isFalse,
      );
    });

    test('rejects empty identities and disposed views', () {
      final guard = AccountRequestGuard();
      final generation = guard.observe('music@example.com');

      expect(
        guard.isCurrent(
          generation: generation,
          expectedEmail: '',
          activeEmail: '',
        ),
        isFalse,
      );
      expect(
        guard.isCurrent(
          generation: generation,
          expectedEmail: 'music@example.com',
          activeEmail: 'music@example.com',
          isMounted: false,
        ),
        isFalse,
      );
    });
  });
}
