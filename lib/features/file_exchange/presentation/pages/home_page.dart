import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:p2pchat/app_services.dart';
import 'package:p2pchat/features/file_exchange/presentation/theme/app_theme.dart';
import 'package:p2pchat/features/file_exchange/presentation/utils/formatters.dart';
import 'package:p2pchat/features/file_exchange/presentation/widgets/common_widgets.dart';
import 'package:p2pchat/features/seeding/data/models/seed_file.dart';
import 'package:p2pchat/features/seeding/presentation/bloc/seeding_bloc.dart';
import 'package:p2pchat/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:p2pchat/features/tracker/data/models/network_file.dart';
import 'package:p2pchat/features/tracker/presentation/bloc/network_catalog_bloc.dart';
import 'package:p2pchat/features/transfer/data/models/transfer_info.dart';
import 'package:p2pchat/features/transfer/presentation/bloc/transfers_bloc.dart';

/// Главный экран. Данные берёт из блоков:
/// - SeedingBloc          — вкладка "My seeding files" (работает и без сети);
/// - NetworkCatalogBloc   — вкладка "Available network files" (нужна сеть);
/// - TransfersBloc        — вкладка "Transfers" и скорости (нужна сеть).
///
/// Без сети два последних блока не предоставлены, поэтому к ним обращаются
/// только когда [status] == online.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.status, required this.onRetry});

  final NetworkStatus status;

  /// Повторная попытка подключения к сети.
  final VoidCallback onRetry;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  HomeTab _tab = HomeTab.discover;
  String _query = '';

  bool get _online => widget.status == NetworkStatus.online;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enterTabAfterFrame();
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final wentOnline =
        widget.status == NetworkStatus.online &&
        oldWidget.status != NetworkStatus.online;

    if (wentOnline) _enterTabAfterFrame();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Вернулись в окно приложения: файлы на диске могли измениться.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<SeedingBloc>().add(const RefreshSeedStatuses());
    }
  }

  // ---------------------------------------------------------------------------
  // Переключение вкладок
  // ---------------------------------------------------------------------------

  void _enterTabAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _enterTab(_tab);
    });
  }

  void _enterTab(HomeTab tab) {
    switch (tab) {
      case HomeTab.discover:
        // Подписка на каталог живёт, только пока открыта вкладка:
        // каждый heartbeat пиров тратит чтения Firestore.
        if (_online) {
          context.read<NetworkCatalogBloc>().add(const StartWatchingCatalog());
        }
      case HomeTab.seeding:
        context.read<SeedingBloc>().add(const RefreshSeedStatuses());
      case HomeTab.transfers:
        break;
    }
  }

  void _leaveTab(HomeTab tab) {
    if (tab == HomeTab.discover && _online) {
      context.read<NetworkCatalogBloc>().add(const StopWatchingCatalog());
    }
  }

  void _select(HomeTab tab) {
    if (tab == _tab) return;

    _leaveTab(_tab);
    setState(() => _tab = tab);
    _enterTab(tab);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 900;

          return Row(
            children: [
              _SidebarContainer(
                compact: compact,
                selected: _tab,
                status: widget.status,
                onSelect: _select,
              ),
              Expanded(
                child: Column(
                  children: [
                    NetworkBanner(
                      status: widget.status,
                      onRetry: widget.onRetry,
                    ),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1240),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 160),
                            child: KeyedSubtree(
                              key: ValueKey(_tab),
                              child: _buildTab(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTab() {
    switch (_tab) {
      case HomeTab.discover:
        return _buildDiscover();
      case HomeTab.transfers:
        return _buildTransfers();
      case HomeTab.seeding:
        return _buildSeeding();
    }
  }

  Widget _unavailableOffline({
    required String title,
    required String subtitle,
  }) {
    final connecting = widget.status == NetworkStatus.connecting;

    return TabScaffold(
      title: title,
      subtitle: subtitle,
      child: EmptyState(
        icon: connecting ? Icons.sync_rounded : Icons.cloud_off_outlined,
        title: connecting ? 'Подключение к сети…' : 'Нет связи с сервером',
        message: connecting
            ? 'Это займёт несколько секунд.'
            : 'Проверьте интернет-соединение и повторите попытку.',
        action: connecting
            ? null
            : FilledButton.icon(
                style: filledButtonStyle,
                onPressed: widget.onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Повторить'),
              ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Вкладка 1: Available network files
  // ---------------------------------------------------------------------------

  Widget _buildDiscover() {
    const title = 'Available network files';
    const subtitle = 'Files shared by other peers right now.';

    if (!_online) return _unavailableOffline(title: title, subtitle: subtitle);

    return TabScaffold(
      title: title,
      subtitle: subtitle,
      trailing: SearchField(onChanged: (v) => setState(() => _query = v)),
      child: BlocBuilder<NetworkCatalogBloc, NetworkCatalogState>(
        builder: (context, catalog) {
          if (catalog.status == CatalogStatus.error) {
            return EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Не удалось загрузить каталог',
              message: catalog.error ?? 'Неизвестная ошибка',
              action: OutlinedButton.icon(
                style: outlinedButtonStyle,
                onPressed: () => context.read<NetworkCatalogBloc>().add(
                  const StartWatchingCatalog(),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Повторить'),
              ),
            );
          }

          if (catalog.status != CatalogStatus.ready) {
            return const Center(child: CircularProgressIndicator());
          }

          final q = _query.trim().toLowerCase();
          final files = catalog.files
              .where((f) => q.isEmpty || f.name.toLowerCase().contains(q))
              .toList();

          if (files.isEmpty) {
            return EmptyState(
              icon: q.isEmpty
                  ? Icons.travel_explore_rounded
                  : Icons.search_off_outlined,
              title: q.isEmpty
                  ? 'Пока никто ничего не раздаёт'
                  : 'Ничего не найдено',
              message: q.isEmpty
                  ? 'Файлы появятся здесь, когда другие пользователи начнут раздачу.'
                  : 'Попробуйте другое название или очистите поиск.',
            );
          }

          return BlocBuilder<TransfersBloc, TransfersState>(
            builder: (context, transfers) {
              return ListView.separated(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: files.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _networkFileRow(files[i], transfers),
              );
            },
          );
        },
      ),
    );
  }

  Widget _networkFileRow(NetworkFile file, TransfersState transfers) {
    final downloading = transfers.isDownloading(file.id);
    final paused = transfers.hasPaused(file.id);

    return RowCard(
      icon: iconForFile(file.name),
      title: file.name,
      subtitle: 'Доступен',
      metrics: [
        Metric(label: 'Size', value: formatBytes(file.size)),
        Metric(
          label: 'Seeders',
          value: '${file.seeders}',
          icon: Icons.arrow_upward_rounded,
        ),
      ],
      actions: [
        downloading
            ? const StatusChip(
                label: 'In transfers',
                color: AppColors.primary,
                background: AppColors.sky,
                icon: Icons.downloading_rounded,
              )
            : FilledButton.icon(
                style: filledButtonStyle,
                // Для файла с недокачанной частью загрузка продолжится с неё.
                onPressed: () => _startDownload(file, resume: paused),
                icon: Icon(
                  paused ? Icons.play_arrow_rounded : Icons.download_rounded,
                  size: 18,
                ),
                label: Text(paused ? 'Resume' : 'Download'),
              ),
      ],
    );
  }

  void _startDownload(NetworkFile file, {bool resume = false}) {
    context.read<TransfersBloc>().add(StartDownload(file));
    _toast(
      resume
          ? 'Загрузка возобновлена: ${file.name}'
          : 'Загрузка начата: ${file.name}',
    );
  }

  // ---------------------------------------------------------------------------
  // Вкладка 2: Transfers
  // ---------------------------------------------------------------------------

  Widget _buildTransfers() {
    const title = 'Transfers';
    const subtitle = 'Track what you are downloading and what has finished.';

    if (!_online) return _unavailableOffline(title: title, subtitle: subtitle);

    return BlocBuilder<TransfersBloc, TransfersState>(
      builder: (context, state) {
        final active = state.activeDownloads;
        final finished = state.finishedDownloads;

        return TabScaffold(
          title: title,
          subtitle: subtitle,
          trailing: finished.isEmpty
              ? null
              : OutlinedButton.icon(
                  style: outlinedButtonStyle,
                  onPressed: () => context.read<TransfersBloc>().add(
                    const ClearFinishedTransfers(),
                  ),
                  icon: const Icon(Icons.clear_all_rounded, size: 18),
                  label: const Text('Clear finished'),
                ),
          child: (active.isEmpty && finished.isEmpty)
              ? const EmptyState(
                  icon: Icons.swap_vert_rounded,
                  title: 'Пока нет загрузок',
                  message:
                      'Выберите файл во вкладке Available network files, '
                      'чтобы начать скачивание.',
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    SectionLabel(text: 'Downloading', count: active.length),
                    if (active.isEmpty)
                      const InlineNote('Сейчас ничего не скачивается.')
                    else
                      for (final t in active) ...[
                        _activeDownloadRow(t),
                        const SizedBox(height: 10),
                      ],
                    const SizedBox(height: 14),
                    SectionLabel(text: 'Finished', count: finished.length),
                    if (finished.isEmpty)
                      const InlineNote('Завершённые загрузки появятся здесь.')
                    else
                      for (final t in finished) ...[
                        _finishedDownloadRow(t),
                        const SizedBox(height: 10),
                      ],
                  ],
                ),
        );
      },
    );
  }

  Widget _activeDownloadRow(TransferInfo t) {
    final transferring = t.status == TransferStatus.active;
    final verifying = t.status == TransferStatus.verifying;
    final paused = t.isPaused;

    final progressText =
        '${formatBytes(t.transferredBytes)} из ${formatBytes(t.totalBytes)}';

    final subtitle = switch (t.status) {
      TransferStatus.connecting => 'Подключение к раздающему…',
      TransferStatus.requesting => 'Запрос файла…',
      TransferStatus.verifying => 'Проверка целостности (SHA-256)…',
      // Прервана по ошибке: показываем причину, иначе обычная пауза.
      TransferStatus.paused => t.error ?? 'Приостановлено: $progressText',
      _ =>
        t.peerCount > 0
            ? '$progressText · раздающих: ${t.peerCount}'
            : progressText,
    };

    final bloc = context.read<TransfersBloc>();

    return RowCard(
      icon: iconForFile(t.name),
      title: t.name,
      subtitle: subtitle,
      subtitleColor: (paused && t.error != null)
          ? AppColors.danger
          : AppColors.muted,
      metrics: [
        Metric(
          label: 'Speed',
          value: transferring ? formatSpeed(t.speedBps) : '—',
        ),
        Metric(label: 'ETA', value: transferring ? formatEta(t.eta) : '—'),
        Metric(
          label: 'Progress',
          value: (transferring || verifying || paused)
              ? formatPercent(t.progress)
              : '—',
        ),
      ],
      // Без значения полоса "бегает": подключение и проверка хеша.
      footer: AppProgressBar(
        value: (transferring || paused) ? t.progress : null,
        paused: paused,
      ),
      actions: [
        if (transferring)
          IconButton.outlined(
            tooltip: 'Pause',
            style: outlinedIconButtonStyle,
            onPressed: () => bloc.add(PauseTransfer(t.id)),
            icon: const Icon(Icons.pause_rounded),
          )
        else if (paused)
          IconButton.outlined(
            tooltip: 'Resume',
            style: outlinedIconButtonStyle,
            onPressed: () => bloc.add(ResumeTransfer(t.id)),
            icon: const Icon(Icons.play_arrow_rounded),
          ),
        if (transferring || paused) const SizedBox(width: 8),
        IconButton.outlined(
          tooltip: 'Cancel and delete downloaded part',
          style: outlinedIconButtonStyle.copyWith(
            foregroundColor: const WidgetStatePropertyAll(AppColors.danger),
          ),
          onPressed: () => bloc.add(CancelTransfer(t.id)),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }

  Widget _finishedDownloadRow(TransferInfo t) {
    final (chip, subtitle, subtitleColor) = switch (t.status) {
      TransferStatus.completed => (
        const StatusChip(
          label: 'Success',
          color: AppColors.success,
          background: AppColors.successBg,
          icon: Icons.check_circle_rounded,
        ),
        t.savedPath ?? 'Файл сохранён',
        AppColors.muted,
      ),
      TransferStatus.cancelled => (
        const StatusChip(
          label: 'Cancelled',
          color: AppColors.muted,
          background: AppColors.background,
          icon: Icons.block_rounded,
        ),
        'Загрузка отменена',
        AppColors.muted,
      ),
      _ => (
        const StatusChip(
          label: 'Failed',
          color: AppColors.danger,
          background: AppColors.dangerBg,
          icon: Icons.error_outline_rounded,
        ),
        t.error ?? 'Ошибка загрузки',
        AppColors.danger,
      ),
    };

    return RowCard(
      icon: iconForFile(t.name),
      title: t.name,
      subtitle: subtitle,
      subtitleColor: subtitleColor,
      metrics: [
        Metric(label: 'Size', value: formatBytes(t.totalBytes)),
        Metric(label: 'Status', width: 130, customValue: chip),
      ],
      actions: [
        if (t.status == TransferStatus.completed)
          OutlinedButton.icon(
            style: outlinedButtonStyle,
            onPressed: () => _openFolder(t.savedPath),
            icon: const Icon(Icons.folder_open_rounded, size: 18),
            label: const Text('Open folder'),
          ),
      ],
    );
  }

  Future<void> _openFolder(String? path) async {
    final exists = path != null && await File(path).exists();
    if (!mounted) return;

    if (!exists) {
      _toast('Файл не найден: возможно, его переместили или удалили');
      return;
    }

    if (Platform.isWindows) {
      // Открывает Проводник с выделенным файлом.
      await Process.run('explorer.exe', ['/select,', path]);
    } else {
      _toast(path);
    }
  }

  // ---------------------------------------------------------------------------
  // Вкладка 3: My seeding files
  // ---------------------------------------------------------------------------

  Widget _buildSeeding() {
    return BlocBuilder<SeedingBloc, SeedingState>(
      builder: (context, seeding) {
        return TabScaffold(
          title: 'My seeding files',
          subtitle: 'Files you are uploading to other peers.',
          trailing: Wrap(
            spacing: 20,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const _AutoSeedSwitch(),
              FilledButton.icon(
                style: filledButtonStyle,
                onPressed: () => _pickFiles(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Share a file'),
              ),
            ],
          ),
          child: _seedingBody(context, seeding),
        );
      },
    );
  }

  Widget _seedingBody(BuildContext context, SeedingState seeding) {
    if (!seeding.loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    if (seeding.seeds.isEmpty && seeding.tasks.isEmpty) {
      return EmptyState(
        icon: Icons.cloud_upload_outlined,
        title: 'Вы пока ничего не раздаёте',
        message: 'Нажмите «Share a file», чтобы начать раздавать файл другим пользователям.',
        action: FilledButton.icon(
          style: filledButtonStyle,
          onPressed: () => _pickFiles(context),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Share a file'),
        ),
      );
    }

    return _withTransfers(
      (transfers) => ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          for (final task in seeding.tasks) ...[
            _hashingTaskRow(task),
            const SizedBox(height: 10),
          ],
          for (final entry in seeding.seeds) ...[
            _seedRow(entry, transfers),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  /// Скорости раздачи берутся из TransfersBloc, а он есть только онлайн.
  Widget _withTransfers(Widget Function(TransfersState transfers) builder) {
    if (!_online) return builder(const TransfersState());

    return BlocBuilder<TransfersBloc, TransfersState>(
      builder: (context, state) => builder(state),
    );
  }

  Widget _hashingTaskRow(HashingTask task) {
    final failed = task.isFailed;

    final subtitle = switch (task.status) {
      HashingStatus.queued => 'В очереди на обработку',
      HashingStatus.hashing =>
        'Вычисление хеша… ${formatPercent(task.progress)}',
      HashingStatus.failed => task.error ?? 'Не удалось добавить файл',
    };

    return RowCard(
      icon: iconForFile(task.name),
      title: task.name,
      subtitle: subtitle,
      subtitleColor: failed ? AppColors.danger : AppColors.muted,
      metrics: [
        Metric(
          label: 'Size',
          value: task.totalBytes > 0 ? formatBytes(task.totalBytes) : '—',
        ),
      ],
      footer: failed
          ? null
          : AppProgressBar(
              value: task.status == HashingStatus.hashing
                  ? task.progress
                  : null,
            ),
      actions: [
        if (failed)
          IconButton.outlined(
            tooltip: 'Dismiss',
            style: outlinedIconButtonStyle,
            onPressed: () =>
                context.read<SeedingBloc>().add(DismissHashingTask(task.path)),
            icon: const Icon(Icons.close_rounded),
          )
        else
          OutlinedButton(
            style: outlinedButtonStyle,
            onPressed: () =>
                context.read<SeedingBloc>().add(CancelHashing(task.path)),
            child: const Text('Cancel'),
          ),
      ],
    );
  }

  Widget _seedRow(SeedEntry entry, TransfersState transfers) {
    final seed = entry.file;

    final (subtitle, subtitleColor) = switch (entry.status) {
      SeedStatus.available => ('Раздаётся', AppColors.primary),
      SeedStatus.missing => ('Файл не найден на диске', AppColors.danger),
      SeedStatus.modified => (
        'Файл изменён: удалите его из списка и добавьте заново',
        AppColors.danger,
      ),
      SeedStatus.unindexed => (
        'Устаревшая запись: удалите её и добавьте файл заново',
        AppColors.danger,
      ),
    };

    return RowCard(
      icon: iconForFile(seed.name),
      title: seed.name,
      subtitle: subtitle,
      subtitleColor: subtitleColor,
      metrics: [
        Metric(label: 'Size', value: formatBytes(seed.size)),
        Metric(
          label: 'Upload speed',
          value: entry.canSeed
              ? formatSpeed(transfers.uploadSpeed(seed.id))
              : '—',
          icon: Icons.arrow_upward_rounded,
        ),
        Metric(
          label: 'Total uploaded',
          value: formatBytes(transfers.uploadedBytes(seed.id)),
        ),
      ],
      actions: [
        OutlinedButton.icon(
          style: dangerOutlinedButtonStyle,
          onPressed: () => _stopSeeding(seed),
          icon: const Icon(Icons.stop_circle_outlined, size: 18),
          label: const Text('Stop seeding'),
        ),
      ],
    );
  }

  Future<void> _pickFiles(BuildContext context) async {
    final result = await FilePicker.pickFiles();

    final paths = result.map((file) => file.path).whereType<String>().toList();

    if (paths.isEmpty) return;

    if (!context.mounted) return;
    // Дальше всё делает SeedingBloc: хеширование, сохранение, а SeedAnnouncer
    // сам анонсирует файл в сети.
    context.read<SeedingBloc>().add(AddSeedFiles(paths));
  }

  void _stopSeeding(SeedFile seed) {
    context.read<SeedingBloc>().add(RemoveSeed(seed.id));

    // Обрываем уже начатые передачи этого файла (иначе они дойдут до конца).
    context.read<AppServices>().online?.coordinator.stopServing(seed.id);

    _toast('Раздача остановлена: ${seed.name}');
  }

  // ---------------------------------------------------------------------------

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          width: 460,
          backgroundColor: AppColors.text,
          duration: const Duration(seconds: 2),
        ),
      );
  }
}

// -----------------------------------------------------------------------------
// Боковая панель с данными из блоков
// -----------------------------------------------------------------------------

/// Отдельный виджет, чтобы частые обновления прогресса перестраивали только
/// боковую панель, а не весь экран.
class _SidebarContainer extends StatelessWidget {
  const _SidebarContainer({
    required this.compact,
    required this.selected,
    required this.status,
    required this.onSelect,
  });

  final bool compact;
  final HomeTab selected;
  final NetworkStatus status;
  final ValueChanged<HomeTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final seedCount = context.watch<SeedingBloc>().state.seeds.length;

    TransfersState? transfers;
    if (status == NetworkStatus.online) {
      transfers = context.watch<TransfersBloc>().state;
    }

    return AppSidebar(
      compact: compact,
      selected: selected,
      status: status,
      badges: {
        HomeTab.transfers: transfers?.activeDownloads.length ?? 0,
        HomeTab.seeding: seedCount,
      },
      downSpeed: transfers?.totalDownloadSpeed ?? 0,
      upSpeed: transfers?.totalUploadSpeed ?? 0,
      onSelect: onSelect,
    );
  }
}

// -----------------------------------------------------------------------------
// Переключатель автораздачи скачанных файлов
// -----------------------------------------------------------------------------

class _AutoSeedSwitch extends StatelessWidget {
  const _AutoSeedSwitch();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, settings) {
        return Tooltip(
          message:
              'Скачанные и проверенные файлы сразу появятся в списке раздачи.\n'
              'Файл можно в любой момент убрать кнопкой Stop seeding.',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(
                value: settings.autoSeedDownloads,
                activeTrackColor: AppColors.primary,
                onChanged: (value) =>
                    context.read<SettingsCubit>().setAutoSeedDownloads(value),
              ),
              const SizedBox(width: 6),
              const Text(
                'Раздавать скачанное',
                style: TextStyle(fontSize: 14, color: AppColors.text),
              ),
            ],
          ),
        );
      },
    );
  }
}
