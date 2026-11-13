import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../core/app_dependencies.dart';
import '../models/player_source.dart';
import '../services/players_api.dart';
import '../services/sniffer.dart';
import '../ui/theme.dart';
import '../ui/widgets/common.dart';
import 'downloads_screen.dart';
import 'player_screen.dart';

/// Главный экран: ввод ID, поиск источников, выбор плеера.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final TextEditingController idController =
      TextEditingController(text: '4640303');
  final FocusNode _searchFocus = FocusNode();

  bool loading = false;
  String? error;
  List<PlayerSource> players = const [];
  String? resolvedId;

  @override
  void dispose() {
    idController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> search() async {
    final id = PlayersApi.extractKinopoiskId(idController.text);
    if (id == null) {
      setState(() {
        error = 'Не вижу числовой ID. Пример: 4640303 '
            'или https://iframe.cloud/see/4640303';
        players = const [];
      });
      return;
    }

    _searchFocus.unfocus();
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final repo = AppDependencies.of(context).playersApi;
      final result = await repo.fetchByKinopoiskId(id);
      if (!mounted) return;
      setState(() {
        resolvedId = id;
        players = result;
        error =
            result.isEmpty ? 'API не вернул ни одного рабочего плеера' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        players = const [];
        error = 'Не удалось получить список плееров: $e\n'
            'Проверьте интернет/VPN — API и плееры режут по региону.';
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void openPlayer(PlayerSource player, {String? url, String? translation}) {
    final iframeUrl = url ?? player.iframeUrl;
    final label = translation ??
        (player.translations.isEmpty
            ? 'По умолчанию'
            : player.translations.first.label);

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          player: player,
          iframeUrl: iframeUrl,
          translationLabel: label,
          kinopoiskId: resolvedId ?? '',
          webView: AppDependencies.of(context).webView,
        ),
      ),
    );
  }

  void chooseTranslation(PlayerSource player) {
    if (player.translations.length <= 1) {
      openPlayer(player);
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _TranslationSheet(
        player: player,
        onSelected: (t) {
          Navigator.of(sheetContext).pop();
          openPlayer(player, url: t.iframeUrl, translation: t.label);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deps = AppDependencies.of(context);

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: const _BrandTitle(),
        actions: [
          ListenableBuilder(
            listenable: deps.appState,
            builder: (context, _) {
              final active = deps.appState.activeCount;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton(
                  tooltip: 'Мои загрузки',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DownloadsScreen(),
                    ),
                  ),
                  icon: Badge(
                    isLabelVisible: active > 0,
                    backgroundColor: AppColors.secondary,
                    textColor: Colors.white,
                    label: Text('$active'),
                    child: const Icon(Icons.download_for_offline_outlined),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        onRefresh: search,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 120),
          children: [
            const _HeroBlock(),
            const SizedBox(height: 22),
            _SearchCard(
              controller: idController,
              focusNode: _searchFocus,
              loading: loading,
              onSearch: search,
              onPaste: () async {
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                final text = data?.text;
                if (text != null && text.isNotEmpty) {
                  idController.text = text;
                }
              },
            ),
            if (error != null) ...[
              const SizedBox(height: 14),
              MessageBanner(message: error!),
            ],
            if (players.isNotEmpty) ...[
              const SizedBox(height: 26),
              SectionHeader(
                title: 'Источники',
                caption: 'Найдено ${players.length} · выберите плеер',
                trailing: StatusPill(
                  label: 'KP ${resolvedId ?? ''}',
                  icon: Icons.movie_outlined,
                ),
              ),
              ...players.map(
                (p) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PlayerTile(
                    player: p,
                    onTap: () => chooseTranslation(p),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 26),
            const _HowItWorks(),
          ],
        ),
      ),
    );
  }
}

class _BrandTitle extends StatelessWidget {
  const _BrandTitle();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(9),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.35),
                blurRadius: 14,
              ),
            ],
          ),
          child:
              const Icon(Icons.graphic_eq, size: 18, color: Color(0xFF00131A)),
        ),
        const SizedBox(width: 10),
        const Text(
          'Rezak',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
      ],
    );
  }
}

class _HeroBlock extends StatelessWidget {
  const _HeroBlock();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShaderMask(
          shaderCallback: (rect) => AppColors.heroGradient.createShader(rect),
          blendMode: BlendMode.srcIn,
          child: const Text(
            'Видео и звук —\nв одном файле',
            style: TextStyle(
              fontSize: 32,
              height: 1.1,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.9,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Находит плееры по ID Кинопоиска, перехватывает HLS/DASH и '
          'склеивает дорожки локально на телефоне.',
          style:
              Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 13.5),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: const [
            StatusPill(label: 'HLS + DASH', icon: Icons.stream),
            StatusPill(
              label: 'ffmpeg на устройстве',
              color: AppColors.tertiary,
              icon: Icons.memory,
            ),
            StatusPill(
              label: 'Без перекодирования',
              color: AppColors.secondary,
              icon: Icons.bolt,
            ),
          ],
        ),
      ],
    );
  }
}

class _SearchCard extends StatelessWidget {
  const _SearchCard({
    required this.controller,
    required this.focusNode,
    required this.loading,
    required this.onSearch,
    required this.onPaste,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool loading;
  final VoidCallback onSearch;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ID ИЛИ ССЫЛКА',
            style: TextStyle(
              fontSize: 10.5,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w800,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('kp-input'),
            controller: controller,
            focusNode: focusNode,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSearch(),
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              hintText: 'https://iframe.cloud/see/4640303',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: IconButton(
                key: const Key('paste-button'),
                tooltip: 'Вставить из буфера',
                icon: const Icon(Icons.content_paste, size: 19),
                onPressed: onPaste,
              ),
            ),
          ),
          const SizedBox(height: 12),
          GradientButton(
            key: const Key('search-button'),
            label: loading ? 'Ищу плееры…' : 'Найти плееры',
            icon: Icons.travel_explore,
            loading: loading,
            onPressed: loading ? null : onSearch,
          ),
        ],
      ),
    );
  }
}

class _PlayerTile extends StatelessWidget {
  const _PlayerTile({required this.player, required this.onTap});

  final PlayerSource player;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasMultiAudio = player.translations.length > 1;

    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.22),
                  AppColors.secondary.withValues(alpha: 0.12),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.stroke),
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              color: AppColors.primary,
              size: 26,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${player.host} · озвучек: ${player.translations.length}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (hasMultiAudio)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: StatusPill(
                label: 'мульти',
                color: AppColors.tertiary,
              ),
            ),
          const Icon(Icons.chevron_right, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  static const List<(IconData, String, String)> _steps = [
    (
      Icons.tag,
      '1 · ID',
      'Сервис iframe.cloud по ID отдаёт список встраиваемых плееров — сам он видео не хранит.'
    ),
    (
      Icons.radar,
      '2 · Сниффер',
      'Плеер открывается во встроенном WebView, перехватываются ссылки на .m3u8 и .mpd.'
    ),
    (
      Icons.call_merge,
      '3 · Склейка',
      'ffmpeg берёт видеопоток и аудиодорожку и копирует их в один mp4 без перекодирования.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Как это работает'),
        ..._steps.map(
          (step) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(step.$1, size: 18, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.$2,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          step.$3,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.45,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TranslationSheet extends StatelessWidget {
  const _TranslationSheet({required this.player, required this.onSelected});

  final PlayerSource player;
  final ValueChanged<Translation> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.stroke,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              player.displayName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            const Text(
              'Выберите озвучку',
              style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),
            ...player.translations.map(
              (t) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GlassCard(
                  onTap: () => onSelected(t),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.record_voice_over_outlined,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t.label,
                          style: const TextStyle(fontSize: 13.5),
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios,
                        size: 13,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Публичный хелпер: понять, что поток — это поток (используется в тестах).
bool looksLikeStream(String url) => Sniffer().inspect(url);
