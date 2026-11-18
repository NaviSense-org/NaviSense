import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navisense/core/theme/navi_colors.dart';
import 'package:navisense/main.dart';

void main() {
  testWidgets('NaviSenseApp renders themed Deep Navy bootstrap scaffold', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const NaviSenseApp());

    expect(find.text('NaviSense'), findsOneWidget);

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, NaviColors.navyDeep);

    expect(
      find.bySemanticsLabel('NaviSense. Hybrid AI spatial guide ready.'),
      findsOneWidget,
    );
  });
}
