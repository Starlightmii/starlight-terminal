import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/catalogue.dart';
import '../../core/console_engine.dart';
import '../../core/palette.dart';
import '../../state/terminal_controller.dart';
import '../widgets/chrome.dart';

/// Browsable observing log, backed by the same notes as `note` / `notes`.
class LogScreen extends StatelessWidget {
  const LogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final term = context.watch<TerminalController>();
    final palette = term.palette;
    final notes = term.notes.reversed.toList();

    return Column(
      children: [
        TermPanel(
          palette: palette,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'OBSERVING LOG',
                      style: TextStyle(
                        fontFamily: 'Mono',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        color: palette.bright,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${notes.length} entr${notes.length == 1 ? 'y' : 'ies'} · '
                      'persisted locally',
                      style: TextStyle(
                        fontFamily: 'Mono',
                        fontSize: 10,
                        color: palette.dim,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: () => _openComposer(context, term),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: palette.mid),
                    color: palette.mid.withValues(alpha: 0.10),
                  ),
                  child: Text(
                    '+ NEW NOTE',
                    style: TextStyle(
                      fontFamily: 'Mono',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: palette.bright,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: notes.isEmpty
              ? _empty(palette, term)
              : ListView.separated(
                  itemCount: notes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final originalIndex = term.notes.length - 1 - i;
                    return _noteCard(
                      context,
                      term,
                      palette,
                      notes[i],
                      originalIndex,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _empty(Palette palette, TerminalController term) {
    return TermPanel(
      palette: palette,
      accent: true,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('✧', style: TextStyle(fontSize: 34, color: palette.dim)),
            const SizedBox(height: 12),
            Text(
              'the log is empty',
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 13,
                color: palette.mid,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'note <text>  ·  or tap + NEW NOTE',
              style: TextStyle(
                fontFamily: 'Mono',
                fontSize: 11,
                color: palette.dim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _noteCard(
    BuildContext context,
    TerminalController term,
    Palette palette,
    SkyNote note,
    int index,
  ) {
    final starName = _starName(note.starId);
    return TermPanel(
      palette: palette,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '#${index + 1}',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: palette.dim,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                fmtClock(note.createdAt),
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 10,
                  color: palette.dim,
                ),
              ),
              if (starName != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: palette.mid.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    '⇒ $starName',
                    style: TextStyle(
                      fontFamily: 'Mono',
                      fontSize: 9,
                      color: palette.mid,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              InkWell(
                onTap: () => term.deleteNote(index),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '✕',
                    style: TextStyle(
                      fontFamily: 'Mono',
                      fontSize: 14,
                      color: palette.err.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            note.text,
            style: TextStyle(
              fontFamily: 'Mono',
              fontSize: 12,
              height: 1.45,
              color: palette.mid,
            ),
          ),
        ],
      ),
    );
  }

  String? _starName(String? id) {
    if (id == null) return null;
    for (final s in kStarCatalogue) {
      if (s.id == id) return s.name;
    }
    return null;
  }

  Future<void> _openComposer(
    BuildContext context,
    TerminalController term,
  ) async {
    final controller = TextEditingController();
    final palette = term.palette;
    final selected = term.selectedStar;

    await showDialog<void>(
      context: context,
      barrierColor: palette.bg.withValues(alpha: 0.82),
      builder: (ctx) => Dialog(
        backgroundColor: palette.panel,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: palette.mid),
          borderRadius: BorderRadius.zero,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '[ NEW LOG ENTRY ]',
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                  color: palette.bright,
                ),
              ),
              if (selected != null) ...[
                const SizedBox(height: 6),
                Text(
                  'tagged ⇒ ${selected.name}',
                  style: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 10,
                    color: palette.dim,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 4,
                minLines: 2,
                cursorColor: palette.bright,
                cursorWidth: 5,
                style: TextStyle(
                  fontFamily: 'Mono',
                  fontSize: 12.5,
                  height: 1.45,
                  color: palette.bright,
                ),
                decoration: InputDecoration(
                  hintText: 'seeing 8/10, M13 resolved at 120×',
                  hintStyle: TextStyle(
                    fontFamily: 'Mono',
                    fontSize: 11.5,
                    color: palette.dim.withValues(alpha: 0.7),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: palette.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: palette.mid),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: palette.line),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(
                      'CANCEL',
                      style: TextStyle(
                        fontFamily: 'Mono',
                        fontSize: 10.5,
                        letterSpacing: 1.2,
                        color: palette.dim,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: () {
                      term.addNote(controller.text);
                      Navigator.of(ctx).pop();
                    },
                    child: Text(
                      'SAVE',
                      style: TextStyle(
                        fontFamily: 'Mono',
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: palette.bright,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
  }
}
