import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/Home_shell.dart';

void main() {
  Widget app() => MaterialApp(
          home: HomeShell(testPages: [
        Builder(
            builder: (context) => Scaffold(
                    body: Column(children: [
                  const Text('today-root'),
                  TextButton(
                      onPressed: () =>
                          Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (context) => Scaffold(
                                appBar: AppBar(title: const Text('detail')),
                                body: Column(children: [
                                  TextButton(
                                      onPressed: () => Navigator.of(context)
                                          .pushReplacement(MaterialPageRoute<
                                                  void>(
                                              builder: (_) => const Scaffold(
                                                  body: Text('next-date')))),
                                      child: const Text('replace-detail')),
                                  TextButton(
                                      onPressed: () =>
                                          HomeShell.selectDestination(
                                              context, 1),
                                      child: const Text('drawer-chat')),
                                ])),
                          )),
                      child: const Text('open-detail')),
                ]))),
        const Scaffold(body: Text('chat-root')),
        const Scaffold(body: Text('review-root')),
        const Scaffold(body: Text('profile-root')),
      ]));

  testWidgets('pushed and replaced pages retain bottom navigation and return',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('open-detail'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.text('replace-detail'));
    await tester.pumpAndSettle();
    expect(find.text('next-date'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('today-root'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('tab and drawer selection from an inner page preserve shell',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('open-detail'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('drawer-chat'));
    await tester.pumpAndSettle();
    expect(find.text('chat-root'), findsOneWidget);
    expect(find.text('detail'), findsNothing);
    expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1);
    await tester.tap(find.text('今天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open-detail'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('回顧'));
    await tester.pumpAndSettle();
    expect(find.text('review-root'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('returning to Today changes its revision so timeline reloads', () {
    expect(
      homeShellTodayRevisionAfterSelection(
        currentIndex: 1,
        selectedIndex: 0,
        currentRevision: 3,
      ),
      4,
    );
  });

  test('selecting other destinations does not rebuild Today', () {
    expect(
      homeShellTodayRevisionAfterSelection(
        currentIndex: 0,
        selectedIndex: 1,
        currentRevision: 3,
      ),
      3,
    );
    expect(
      homeShellTodayRevisionAfterSelection(
        currentIndex: 0,
        selectedIndex: 0,
        currentRevision: 3,
      ),
      3,
    );
  });
}
