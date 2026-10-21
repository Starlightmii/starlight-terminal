import 'package:flutter/foundation.dart';

/// A single pi slash command, as documented at pi.dev/docs/latest/slash-commands.
///
/// The app cannot shell out to a real `pi` binary (it needs Node 22.19, which
/// Android cannot host), so every one of these is implemented natively against
/// the session store, the model client and the VFS. The command *names* and
/// argument shapes deliberately match upstream, so muscle memory carries over.
@immutable
class PiCommand {
  const PiCommand(
    this.name,
    this.usage,
    this.summary, {
    this.group = PiCommandGroup.models,
    this.argHint,
  });

  /// Without the leading slash, e.g. `model`.
  final String name;

  /// Full usage string shown in the command index.
  final String usage;

  final String summary;
  final PiCommandGroup group;

  /// Completion hint appended to `/name ` when tab-completing.
  final String? argHint;
}

enum PiCommandGroup { models, session, share, runtime }

const Map<PiCommandGroup, String> kPiGroupLabel = {
  PiCommandGroup.models: 'MODELS & SETTINGS',
  PiCommandGroup.session: 'SESSIONS & CONTEXT',
  PiCommandGroup.share: 'SHARE & EXPORT',
  PiCommandGroup.runtime: 'RUNTIME',
};

/// The built-in command set, mirroring pi's own reference.
const List<PiCommand> kPiCommands = [
  // ── models & settings ───────────────────────────────────────────────────
  PiCommand('/model', '/model [provider/model]',
      'Select a model', argHint: '[provider/model]'),
  PiCommand('/thinking', '/thinking [level]',
      'Set the thinking level', argHint: '[off|low|medium|high]'),
  PiCommand('/scoped-models', '/scoped-models',
      'Configure the models used by interactive cycling'),
  PiCommand('/login', '/login [provider]', 'Add provider authentication',
      argHint: '[provider]'),
  PiCommand('/logout', '/logout', 'Remove provider authentication'),
  PiCommand('/settings', '/settings', 'Open settings'),

  // ── sessions & context ──────────────────────────────────────────────────
  PiCommand('/new', '/new', 'Start a new session',
      group: PiCommandGroup.session),
  PiCommand('/resume', '/resume', 'Switch to another saved session',
      group: PiCommandGroup.session),
  PiCommand('/name', '/name [name]', 'Set the session display name',
      group: PiCommandGroup.session, argHint: '[name]'),
  PiCommand('/session', '/session', 'Session information and statistics',
      group: PiCommandGroup.session),
  PiCommand('/tree', '/tree', 'Navigate the session tree',
      group: PiCommandGroup.session),
  PiCommand('/fork', '/fork', 'Fork from an earlier message',
      group: PiCommandGroup.session),
  PiCommand('/clone', '/clone', 'Duplicate the current session',
      group: PiCommandGroup.session),
  PiCommand('/compact', '/compact [instructions]', 'Compact the context',
      group: PiCommandGroup.session, argHint: '[instructions]'),
  PiCommand('/context', '/context', 'Show context window usage',
      group: PiCommandGroup.session),

  // ── share & export ──────────────────────────────────────────────────────
  PiCommand('/copy', '/copy', 'Copy the last assistant message',
      group: PiCommandGroup.share),
  PiCommand('/export', '/export [path]', 'Export the session as JSONL',
      group: PiCommandGroup.share, argHint: '[path]'),
  PiCommand('/share', '/share', 'Copy a shareable session digest',
      group: PiCommandGroup.share),

  // ── runtime ─────────────────────────────────────────────────────────────
  PiCommand('/skills', '/skills', 'List discovered skills',
      group: PiCommandGroup.runtime),
  PiCommand('/skill', '/skill:<name> [args]', 'Run a skill',
      group: PiCommandGroup.runtime, argHint: ':name'),
  PiCommand('/reload', '/reload', 'Reload skills, templates and themes',
      group: PiCommandGroup.runtime),
  PiCommand('/hotkeys', '/hotkeys', 'Show active key bindings',
      group: PiCommandGroup.runtime),
  PiCommand('/changelog', '/changelog', "Show what's new",
      group: PiCommandGroup.runtime),
  PiCommand('/version', '/version', 'Print the pi version',
      group: PiCommandGroup.runtime),
  PiCommand('/update', '/update', 'Check the registry for a newer pi',
      group: PiCommandGroup.runtime),
  PiCommand('/status', '/status', 'Install, model and provider state',
      group: PiCommandGroup.runtime),
  PiCommand('/debug', '/debug', 'Dump a diagnostic trace',
      group: PiCommandGroup.runtime),
  PiCommand('/bug', '/bug [description]', 'Prepare a bug report',
      group: PiCommandGroup.runtime, argHint: '[description]'),
  PiCommand('/help', '/help', 'This command index',
      group: PiCommandGroup.runtime),
  PiCommand('/clear', '/clear', 'Clear the transcript',
      group: PiCommandGroup.runtime),
  PiCommand('/quit', '/quit', 'Close the session',
      group: PiCommandGroup.runtime),
];

/// A skill: a named prompt macro, exactly as pi discovers them from
/// `.pi/skills/*.md`. Ours are seeded into the VFS so `ls ~/.pi/skills` works.
@immutable
class PiSkill {
  const PiSkill(this.name, this.summary, this.prompt);
  final String name;
  final String summary;
  final String prompt;
}

const List<PiSkill> kPiSkills = [
  PiSkill(
    'research',
    'Break a question down and name what to verify',
    'Research the following. Split it into sub-questions, state what is known, '
        'what is uncertain, and what should be checked next. Never invent '
        'sources. Finish with a line beginning NEXT: naming the single most '
        'useful next step.',
  ),
  PiSkill(
    'review',
    'Review a patch for defects, not style',
    'Review the following diff for correctness defects only: null safety, '
        'error paths, resource leaks, off-by-one, and race conditions. Quote '
        'the offending line, say why it is wrong, and give the minimal fix. '
        'Say nothing about formatting.',
  ),
  PiSkill(
    'explain',
    'Explain code to someone who has to maintain it',
    'Explain the following code to a maintainer who has never seen it. Lead '
        'with what it is for, then how data moves through it, then the two '
        'things most likely to break. Plain prose, no tables.',
  ),
  PiSkill(
    'refactor',
    'Propose the smallest change that fixes the structure',
    'Propose a refactor of the following. The smallest change that improves '
        'structure wins. Give the before/after shape, the risk of the change, '
        'and what test would prove it safe.',
  ),
  PiSkill(
    'test',
    'Write the tests that would actually catch regressions',
    'Write tests for the following. Cover the happy path once, then spend the '
        'rest of the budget on boundaries, nulls, empty inputs and error paths. '
        'Name each test after the bug it prevents.',
  ),
  PiSkill(
    'summarise',
    'Compress a long thread without losing decisions',
    'Summarise the following. Keep every decision, every named actor and every '
        'open question. Drop pleasantries and restatement. Target one third of '
        'the original length.',
  ),
  PiSkill(
    'commit',
    'Draft a commit message that explains why',
    'Write a commit message for the following change. Subject line under 72 '
        'characters, imperative mood. Body explains why the change was needed '
        'and what it does not do. No emoji.',
  ),
  PiSkill(
    'shell',
    'Turn an intent into a safe shell command',
    'Turn the following intent into a single shell command. Explain every flag '
        'you use in one short line. If the command is destructive, say so and '
        'give the dry-run form first.',
  ),
];

PiSkill? skillByName(String name) {
  final n = name.trim().toLowerCase();
  for (final s in kPiSkills) {
    if (s.name == n) return s;
  }
  return null;
}

/// Resolve a prefix to the commands that start with it — used for the
/// suggestion popup and for tab completion.
List<PiCommand> completeCommand(String typed) {
  final t = typed.trimLeft();
  if (!t.startsWith('/')) return const [];
  final body = t.substring(1).toLowerCase();
  if (body.isEmpty) return kPiCommands;
  return kPiCommands
      .where((c) => c.name.substring(1).startsWith(body))
      .toList();
}

/// Resolve a `/skill:` prefix against the skill list.
List<PiSkill> completeSkill(String typed) {
  const prefix = '/skill:';
  if (!typed.toLowerCase().startsWith(prefix)) return const [];
  final body = typed.substring(prefix.length).toLowerCase();
  return kPiSkills.where((s) => s.name.startsWith(body)).toList();
}
