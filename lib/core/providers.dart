import 'package:flutter/foundation.dart';

/// What a provider endpoint can be used for.
enum ProviderKind { llm, image, video }

/// A first-class model provider: someone's API, their key, their model id.
///
/// The terminal ships with presets for the common endpoints but every field is
/// editable, so an OpenAI-compatible gateway (Ollama, vLLM, LiteLLM, OpenRouter,
/// a corporate proxy) works exactly like a first-party vendor.
@immutable
class Provider {
  const Provider({
    required this.id,
    required this.label,
    required this.kind,
    required this.baseUrl,
    required this.model,
    this.apiKey = '',
    this.enabled = true,
    this.isPreset = false,
    this.notes = '',
    this.maxTokens = 1024,
    this.temperature = 0.7,
  });

  /// Stable local identifier, e.g. `groq` or `custom-1704`.
  final String id;

  /// Display name shown in `keys list` and the KEYS panel.
  final String label;

  final ProviderKind kind;

  /// Base URL up to (not including) the path, e.g. `https://api.openai.com/v1`.
  final String baseUrl;

  /// Model identifier sent in the request body.
  final String model;

  final String apiKey;
  final bool enabled;

  /// True when this came from the built-in preset list.
  final bool isPreset;

  final String notes;
  final int maxTokens;
  final double temperature;

  /// A usable provider needs an endpoint and a key. Presets without keys are
  /// shown but cannot be activated.
  bool get ready => enabled && apiKey.trim().isNotEmpty;

  /// Never expose the full secret in the UI or in logs.
  String get maskedKey {
    final k = apiKey.trim();
    if (k.isEmpty) return '—';
    if (k.length <= 8) return '${k.substring(0, 2)}${'•' * 6}';
    return '${k.substring(0, 4)}${'•' * 8}${k.substring(k.length - 4)}';
  }

  /// Heuristic: does this look like a real key rather than a placeholder?
  bool get looksPlausible {
    final k = apiKey.trim();
    if (k.isEmpty) return false;
    if (k.length < 16) return false;
    if (k.toLowerCase().contains('your') || k.contains('xxx')) return false;
    return true;
  }

  String get kindLabel => switch (kind) {
        ProviderKind.llm => 'LLM',
        ProviderKind.image => 'IMAGE',
        ProviderKind.video => 'VIDEO',
      };

  /// The chat-completions endpoint for this provider.
  Uri get chatEndpoint => Uri.parse('$baseUrl/chat/completions');

  /// The provider id pi uses in its own `auth.json` / catalog.
  ///
  /// These are pi's ids, not ours: pi keys credentials by provider, so the
  /// mapping has to be exact or the key is written where pi will not read it.
  String get piProviderId => switch (id) {
        'openai' => 'openai',
        'anthropic' => 'anthropic',
        'gemini' => 'google',
        'groq' => 'groq',
        'openrouter' => 'openrouter',
        'deepseek' => 'deepseek',
        'mistral' => 'mistral',
        'together' => 'together',
        'zai' => 'zai',
        'ollama' => 'ollama',
        _ => id,
      };

  /// Image generation endpoint (OpenAI-compatible `/images/generations`).
  Uri get imageEndpoint => Uri.parse('$baseUrl/images/generations');

  Provider copyWith({
    String? label,
    ProviderKind? kind,
    String? baseUrl,
    String? model,
    String? apiKey,
    bool? enabled,
    String? notes,
    int? maxTokens,
    double? temperature,
  }) {
    return Provider(
      id: id,
      label: label ?? this.label,
      kind: kind ?? this.kind,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      apiKey: apiKey ?? this.apiKey,
      enabled: enabled ?? this.enabled,
      isPreset: isPreset,
      notes: notes ?? this.notes,
      maxTokens: maxTokens ?? this.maxTokens,
      temperature: temperature ?? this.temperature,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'kind': kind.name,
        'baseUrl': baseUrl,
        'model': model,
        'apiKey': apiKey,
        'enabled': enabled,
        'isPreset': isPreset,
        'notes': notes,
        'maxTokens': maxTokens,
        'temperature': temperature,
      };

  static Provider fromJson(Map<String, dynamic> j) {
    return Provider(
      id: (j['id'] ?? '').toString(),
      label: (j['label'] ?? 'provider').toString(),
      kind: ProviderKind.values.firstWhere(
        (k) => k.name == j['kind'],
        orElse: () => ProviderKind.llm,
      ),
      baseUrl: (j['baseUrl'] ?? '').toString(),
      model: (j['model'] ?? '').toString(),
      apiKey: (j['apiKey'] ?? '').toString(),
      enabled: j['enabled'] as bool? ?? true,
      isPreset: j['isPreset'] as bool? ?? false,
      notes: (j['notes'] ?? '').toString(),
      maxTokens: (j['maxTokens'] as num?)?.toInt() ?? 1024,
      temperature: (j['temperature'] as num?)?.toDouble() ?? 0.7,
    );
  }
}

/// Built-in provider presets. Keys are intentionally blank — the user pastes
/// their own into the KEYS panel or `keys set`.
abstract final class ProviderPresets {
  static const List<Provider> all = <Provider>[
    // ── LLM ────────────────────────────────────────────────────────────
    Provider(
      id: 'openai',
      label: 'OpenAI',
      kind: ProviderKind.llm,
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-4o-mini',
      isPreset: true,
      notes: 'Chat completions. Also serves /images/generations.',
    ),
    Provider(
      id: 'anthropic',
      label: 'Anthropic',
      kind: ProviderKind.llm,
      baseUrl: 'https://api.anthropic.com/v1',
      model: 'claude-sonnet-4-5',
      isPreset: true,
      notes: 'Messages API. Wire an OpenAI-compat proxy if needed.',
    ),
    Provider(
      id: 'groq',
      label: 'Groq',
      kind: ProviderKind.llm,
      baseUrl: 'https://api.groq.com/openai/v1',
      model: 'llama-3.3-70b-versatile',
      isPreset: true,
      notes: 'OpenAI-compatible, very fast inference.',
    ),
    Provider(
      id: 'openrouter',
      label: 'OpenRouter',
      kind: ProviderKind.llm,
      baseUrl: 'https://openrouter.ai/api/v1',
      model: 'anthropic/claude-3.5-sonnet',
      isPreset: true,
      notes: 'One key, hundreds of models.',
    ),
    Provider(
      id: 'deepseek',
      label: 'DeepSeek',
      kind: ProviderKind.llm,
      baseUrl: 'https://api.deepseek.com/v1',
      model: 'deepseek-chat',
      isPreset: true,
      notes: 'OpenAI-compatible. Cheap reasoning models.',
    ),
    Provider(
      id: 'mistral',
      label: 'Mistral',
      kind: ProviderKind.llm,
      baseUrl: 'https://api.mistral.ai/v1',
      model: 'mistral-large-latest',
      isPreset: true,
      notes: 'OpenAI-compatible endpoint.',
    ),
    Provider(
      id: 'together',
      label: 'Together AI',
      kind: ProviderKind.llm,
      baseUrl: 'https://api.together.xyz/v1',
      model: 'meta-llama/Llama-3.3-70B-Instruct-Turbo',
      isPreset: true,
      notes: 'Open-source model hosting, OpenAI-compatible.',
    ),
    Provider(
      id: 'ollama',
      label: 'Ollama (local)',
      kind: ProviderKind.llm,
      baseUrl: 'http://localhost:11434/v1',
      model: 'llama3.1',
      isPreset: true,
      notes: 'Runs on your machine. Key can be any non-empty string.',
    ),
    Provider(
      id: 'gemini',
      label: 'Google Gemini',
      kind: ProviderKind.llm,
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      model: 'gemini-2.0-flash',
      isPreset: true,
      notes: 'OpenAI-compatible gateway.',
    ),
    Provider(
      id: 'zai',
      label: 'Z.AI',
      kind: ProviderKind.llm,
      baseUrl: 'https://api.z.ai/api/paas/v4',
      model: 'glm-4-plus',
      isPreset: true,
      notes: 'The provider Pi documents first.',
    ),

    // ── IMAGE ──────────────────────────────────────────────────────────
    Provider(
      id: 'openai-image',
      label: 'OpenAI Images',
      kind: ProviderKind.image,
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-image-1',
      isPreset: true,
      notes: 'POST /images/generations, returns b64_json.',
    ),
    Provider(
      id: 'fal',
      label: 'fal.ai',
      kind: ProviderKind.image,
      baseUrl: 'https://fal.run',
      model: 'fal-ai/flux/schnell',
      isPreset: true,
      notes: 'Fast diffusion. Endpoint per model.',
    ),
    Provider(
      id: 'replicate',
      label: 'Replicate',
      kind: ProviderKind.image,
      baseUrl: 'https://api.replicate.com/v1',
      model: 'black-forest-labs/flux-schnell',
      isPreset: true,
      notes: 'Async predictions API.',
    ),
    Provider(
      id: 'stability',
      label: 'Stability AI',
      kind: ProviderKind.image,
      baseUrl: 'https://api.stability.ai/v2beta',
      model: 'sd3.5-large',
      isPreset: true,
      notes: 'Stable Diffusion 3.5.',
    ),

    // ── VIDEO ──────────────────────────────────────────────────────────
    Provider(
      id: 'runway',
      label: 'Runway',
      kind: ProviderKind.video,
      baseUrl: 'https://api.dev.runwayml.com/v1',
      model: 'gen4_turbo',
      isPreset: true,
      notes: 'Image-to-video, async job polling.',
    ),
    Provider(
      id: 'luma',
      label: 'Luma Dream Machine',
      kind: ProviderKind.video,
      baseUrl: 'https://api.lumalabs.ai/dream-machine/v1',
      model: 'ray-2',
      isPreset: true,
      notes: 'Text/image to video.',
    ),
    Provider(
      id: 'pika',
      label: 'Pika',
      kind: ProviderKind.video,
      baseUrl: 'https://api.pika.art/v1',
      model: 'pika-2.2',
      isPreset: true,
      notes: 'Short generative clips.',
    ),
  ];

  /// CORS reality check for the browser build. Most vendor APIs reject
  /// cross-origin calls from a page, so a proxy (or the Android build) is
  /// required. Keys still work unchanged.
  static bool typicallyAllowsBrowserCors(Provider p) {
    switch (p.id) {
      case 'openai':
      case 'openai-image':
      case 'anthropic':
      case 'groq':
      case 'openrouter':
      case 'fal':
      case 'stability':
      case 'zai':
        return true; // sends permissive ACAO, or works via proxy
      case 'ollama':
        return true; // local server, same-machine
      default:
        return false;
    }
  }
}
