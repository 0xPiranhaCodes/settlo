import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo/main.dart';

void main() {
  testWidgets('boots to the empty root route', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SettloApp()));

    final router = GoRouter.of(tester.element(find.byType(SizedBox).last));
    expect(router.state.uri.path, '/');
  });
}
