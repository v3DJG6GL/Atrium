import 'package:core_subtitles/core_subtitles.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {double? width, bool disableAnimations = false}) {
  Widget body = Center(
    child: width == null ? child : SizedBox(width: width, child: child),
  );
  if (disableAnimations) {
    body = Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: Center(child: child),
      ),
    );
  }
  return MaterialApp(
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    home: Scaffold(body: body),
  );
}

List<SubtitleChip> _chips(List<String> codes) => [
      for (final c in codes)
        SubtitleChip(
          key: '$c|',
          code2: c,
          forced: false,
          hi: false,
          state: SubtitleState.present,
        ),
    ];

void main() {
  group('SubtitleTrackChip', () {
    testWidgets('announces language, flags and state', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          const Wrap(
            spacing: 24,
            children: [
              SubtitleTrackChip(code2: 'de', state: SubtitleState.present),
              SubtitleTrackChip(
                code2: 'en',
                languageName: 'English',
                state: SubtitleState.embedded,
                hi: true,
              ),
              SubtitleTrackChip(
                code2: 'fr',
                state: SubtitleState.missing,
                forced: true,
              ),
            ],
          ),
        ),
      );
      expect(find.bySemanticsLabel('de, subtitle file'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'English, hearing impaired, embedded subtitle track',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('fr, forced, missing subtitle'),
        findsOneWidget,
      );
      expect(find.text('DE'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('shows only the forced badge when forced and HI',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          const SubtitleTrackChip(
            code2: 'en',
            state: SubtitleState.present,
            forced: true,
            hi: true,
          ),
        ),
      );
      expect(find.text('F'), findsOneWidget);
      expect(find.byIcon(Icons.hearing), findsNothing);
      expect(
        find.bySemanticsLabel('en, forced, hearing impaired, subtitle file'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('shows the ear badge for HI', (tester) async {
      await tester.pumpWidget(
        _app(
          SubtitleTrackChip.fromChip(
            const SubtitleChip(
              key: 'en|h',
              code2: 'en',
              forced: false,
              hi: true,
              state: SubtitleState.missing,
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.hearing), findsOneWidget);
      expect(find.text('F'), findsNothing);
    });
  });

  group('AudioPill and OverflowTag', () {
    testWidgets('announce themselves', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 24,
            children: [
              AudioPill.fromTag(
                const AudioTag(code2: 'en', name: 'English', original: true),
              ),
              const AudioPill(code2: 'de'),
              const OverflowTag(count: 3),
            ],
          ),
        ),
      );
      expect(
        find.bySemanticsLabel('English audio, original language'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('de audio'), findsOneWidget);
      expect(find.byIcon(Icons.home_rounded), findsOneWidget);
      expect(find.bySemanticsLabel('3 more'), findsOneWidget);
      expect(find.text('+3'), findsOneWidget);
      handle.dispose();
    });
  });

  group('LanguageLines', () {
    final subtitles = _chips(['de', 'en', 'es', 'fr', 'it']);

    testWidgets('collapses what does not fit into +N', (tester) async {
      await tester.pumpWidget(
        _app(LanguageLines(subtitles: subtitles), width: 100),
      );
      expect(find.byType(SubtitleTrackChip), findsOneWidget);
      expect(find.text('+4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows every chip when there is room', (tester) async {
      await tester.pumpWidget(
        _app(LanguageLines(subtitles: subtitles), width: 400),
      );
      expect(find.byType(SubtitleTrackChip), findsNWidgets(5));
      expect(find.byType(OverflowTag), findsNothing);
    });

    testWidgets('splits audio and subtitles into two columns', (tester) async {
      await tester.pumpWidget(
        _app(
          LanguageLines(
            audio: const [AudioTag(code2: 'en', name: 'English')],
            subtitles: subtitles,
          ),
          width: 400,
        ),
      );
      expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);
      expect(find.byIcon(Icons.closed_caption_outlined), findsOneWidget);
      expect(find.byType(AudioPill), findsOneWidget);
      // 200 px per column fits all five chips at sm.
      expect(find.byType(SubtitleTrackChip), findsNWidgets(5));
    });

    testWidgets('leaves a blank column without subtitle data', (tester) async {
      await tester.pumpWidget(
        _app(
          const LanguageLines(
            audio: [AudioTag(code2: 'en', name: 'English')],
            subtitles: null,
          ),
          width: 300,
        ),
      );
      expect(find.byIcon(Icons.closed_caption_outlined), findsNothing);
      expect(find.byType(AudioPill), findsOneWidget);
    });

    testWidgets('is one labelled button when tappable', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(
        _app(
          LanguageLines(
            subtitles: subtitles,
            onTap: () => taps++,
            semanticLabel: 'Episode subtitles',
          ),
          width: 400,
        ),
      );
      expect(find.bySemanticsLabel('Episode subtitles'), findsOneWidget);
      await tester.tap(find.byType(LanguageLines));
      expect(taps, 1);
      handle.dispose();
    });
  });

  group('SeasonGapBadge', () {
    testWidgets('is hidden at zero', (tester) async {
      await tester.pumpWidget(_app(const SeasonGapBadge(gaps: 0)));
      expect(find.byIcon(Icons.closed_caption_outlined), findsNothing);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('announces one episode in the singular', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(const SeasonGapBadge(gaps: 1)));
      expect(
        find.bySemanticsLabel('1 episode missing subtitles'),
        findsOneWidget,
      );
      expect(find.text('1'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('announces several episodes in the plural', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(const SeasonGapBadge(gaps: 3)));
      expect(
        find.bySemanticsLabel('3 episodes missing subtitles'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('SearchingIndicator', () {
    testWidgets('offers a restart only after 30 seconds', (tester) async {
      final since = DateTime(2026, 1, 1, 12);
      var clock = since;
      var restarts = 0;
      await tester.pumpWidget(
        _app(
          SearchingIndicator(
            since: since,
            now: () => clock,
            onRestart: () => restarts++,
          ),
        ),
      );
      expect(find.text('Searching providers…'), findsOneWidget);
      expect(
        find.text(
          'Bazarr asks every subtitle provider in turn. '
          'This can take a minute.',
        ),
        findsOneWidget,
      );
      expect(find.text('0:00'), findsOneWidget);
      expect(find.text('Restart search'), findsNothing);

      clock = since.add(const Duration(seconds: 29));
      await tester.pump(const Duration(seconds: 29));
      expect(find.text('0:29'), findsOneWidget);
      expect(find.text('Restart search'), findsNothing);

      clock = since.add(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('0:30'), findsOneWidget);
      expect(find.text('Restart search'), findsOneWidget);
      expect(find.textContaining('Still searching.'), findsOneWidget);

      await tester.tap(find.text('Restart search'));
      expect(restarts, 1);
    });

    testWidgets('never offers a restart without onRestart', (tester) async {
      final since = DateTime(2026, 1, 1, 12);
      await tester.pumpWidget(
        _app(
          SearchingIndicator(
            since: since,
            now: () => since.add(const Duration(minutes: 2)),
          ),
        ),
      );
      expect(find.textContaining('Still searching.'), findsOneWidget);
      expect(find.text('Restart search'), findsNothing);
      expect(find.text('2:00'), findsOneWidget);
    });

    testWidgets('shows a still magnifier with reduced motion', (tester) async {
      final since = DateTime(2026, 1, 1, 12);
      await tester.pumpWidget(
        _app(
          SearchingIndicator(since: since, now: () => since),
          disableAnimations: true,
        ),
      );
      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.byType(ExpressiveProgressIndicator), findsNothing);
    });
  });

  group('ElapsedText', () {
    testWidgets('announces the seconds with the right plural', (tester) async {
      final handle = tester.ensureSemantics();
      final since = DateTime(2026, 1, 1, 12);
      var clock = since.add(const Duration(seconds: 1));
      await tester.pumpWidget(
        _app(ElapsedText(since: since, now: () => clock)),
      );
      expect(find.bySemanticsLabel('Searching for 1 second'), findsOneWidget);
      clock = since.add(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      expect(find.bySemanticsLabel('Searching for 2 seconds'), findsOneWidget);
      expect(find.text('0:02'), findsOneWidget);
      handle.dispose();
    });
  });

  group('formatElapsed', () {
    test('formats m:ss', () {
      expect(formatElapsed(Duration.zero), '0:00');
      expect(formatElapsed(const Duration(seconds: 42)), '0:42');
      expect(formatElapsed(const Duration(seconds: 65)), '1:05');
      expect(formatElapsed(const Duration(minutes: 75)), '75:00');
      expect(formatElapsed(const Duration(milliseconds: 1999)), '0:01');
      expect(formatElapsed(const Duration(seconds: -5)), '0:00');
    });
  });

  group('tags in a Wrap or Column', () {
    // A bounded width must not stretch a tag; it used to fill the line.
    for (final (String name, Widget tag) in <(String, Widget)>[
      (
        'subtitle chip',
        const SubtitleTrackChip(code2: 'en', state: SubtitleState.present),
      ),
      ('audio pill', const AudioPill(code2: 'fr', original: true)),
      ('overflow tag', const OverflowTag(count: 3)),
    ]) {
      testWidgets('$name keeps to its content', (tester) async {
        await tester.pumpWidget(
          _app(
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(children: [tag]),
                tag,
              ],
            ),
            width: 400,
          ),
        );
        final finder = find.byWidget(tag);
        expect(finder, findsNWidgets(2));
        for (final element in finder.evaluate()) {
          final size = (element.renderObject! as RenderBox).size;
          expect(size.width, lessThan(80));
        }
      });
    }
  });
}
