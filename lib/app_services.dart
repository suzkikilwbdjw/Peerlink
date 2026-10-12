import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:p2pchat/features/auth/data/services/auth_services.dart';
import 'package:p2pchat/features/connection/data/services/peer_connection_manager.dart';
import 'package:p2pchat/features/connection/data/services/webrtc_services.dart';
import 'package:p2pchat/features/seeding/data/models/seed_file.dart';
import 'package:p2pchat/features/seeding/data/repositories/seed_repository.dart';
import 'package:p2pchat/features/seeding/data/services/seed_announcer.dart';
import 'package:p2pchat/features/seeding/presentation/bloc/seeding_bloc.dart';
import 'package:p2pchat/features/settings/data/repositories/settings_repository.dart';
import 'package:p2pchat/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:p2pchat/features/signaling/data/repositories/signaling_repository.dart';
import 'package:p2pchat/features/tracker/data/models/network_file.dart';
import 'package:p2pchat/features/tracker/data/repositories/tracker_repository.dart';
import 'package:p2pchat/features/tracker/presentation/bloc/network_catalog_bloc.dart';
import 'package:p2pchat/features/transfer/data/repositories/partial_download_repository.dart';
import 'package:p2pchat/features/transfer/data/services/auto_seeder.dart';
import 'package:p2pchat/features/transfer/data/services/manifest_store.dart';
import 'package:p2pchat/features/transfer/data/services/transfer_coordinator.dart';
import 'package:p2pchat/features/transfer/presentation/bloc/transfers_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Всё, что требует связи с Firebase. Создаётся только после успешного входа.
class OnlineServices {
  OnlineServices({
    required this.uid,
    required this.manager,
    required this.coordinator,
    required this.announcer,
    required this.autoSeeder,
    required this.catalogBloc,
    required this.transfersBloc,
  });

  final String uid;
  final PeerConnectionManager manager;
  final TransferCoordinator coordinator;
  final SeedAnnouncer announcer;
  final AutoSeeder autoSeeder;
  final NetworkCatalogBloc catalogBloc;
  final TransfersBloc transfersBloc;

  /// Корректное завершение: убираем пира из каталога и закрываем соединения.
  Future<void> shutdown() async {
    await autoSeeder.dispose();
    await announcer.dispose();
    await manager.dispose();
  }
}

/// Владелец долгоживущих объектов приложения.
///
/// Локальная часть (список раздач) работает всегда. Сетевая часть
/// ([online]) появляется после [goOnline] и не мешает работе без сети.
class AppServices {
  AppServices({required SharedPreferences prefs})
    : this._(prefs, ManifestStore(directory: _manifestsDirectory));

  AppServices._(SharedPreferences prefs, this.manifests)
    : _prefs = prefs,
      settingsCubit = SettingsCubit(SettingsRepository(prefs)),
      seedingBloc = SeedingBloc(SeedRepository(prefs), manifests)
        ..add(const LoadSeeds());

  /// Манифесты файлов (хеши кусков). Нужны и раздаче, и загрузке.
  final ManifestStore manifests;

  static Future<Directory> _manifestsDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'manifests'));
  }

  final SharedPreferences _prefs;

  /// Настройки (например, автораздача скачанных файлов). Работают и офлайн.
  final SettingsCubit settingsCubit;

  /// Один на всё приложение: его же слушают анонсер и раздающая сторона.
  final SeedingBloc seedingBloc;

  /// Один экземпляр на приложение: у него общий набор сессий.
  final WebRTCService webrtc = WebRTCService();

  OnlineServices? online;

  Future<bool>? _pending;

  /// Пытается войти в Firebase и поднять сетевую часть. Безопасно вызывать
  /// повторно (кнопка "Повторить"): параллельные вызовы схлопываются.
  Future<bool> goOnline() {
    return _pending ??= _goOnline().whenComplete(() => _pending = null);
  }

  Future<bool> _goOnline() async {
    if (online != null) return true;

    try {
      final uid = await AuthService().ensureSignedIn().timeout(
        const Duration(seconds: 15),
      );

      final tracker = TrackerRepository();

      final manager = PeerConnectionManager(
        webrtc: webrtc,
        signaling: SignalingRepository(),
        selfUid: uid,
        // Входящие соединения принимаем, только пока есть что раздавать.
        acceptIncoming: () => seedingBloc.state.seeds.any((e) => e.canSeed),
      )..start();

      final coordinator = TransferCoordinator(
        manager: manager,
        webrtc: webrtc,
        lookupSeed: _lookupSeed,
        downloadsDirectory: _downloadsDirectory,
        manifests: manifests,
        partials: PartialDownloadRepository(_prefs),
        // Для возобновления загрузки без каталога: кто раздаёт файл сейчас.
        findSeeders: (fileId) async {
          final peers = await tracker.fetchPeers();

          final catalog = buildCatalog(
            peers: peers,
            selfUid: uid,
            now: DateTime.now(),
            ttl: const Duration(minutes: 5),
          );

          for (final file in catalog) {
            if (file.id == fileId) return file.seederIds;
          }
          return const <String>[];
        },
      )..start();

      final announcer = SeedAnnouncer(
        tracker: tracker,
        uid: uid,
        seeding: seedingBloc,
      )..start();

      // Скачанные и проверенные файлы сразу попадают в раздачу, если опция
      // включена. Анонсирует их в сети уже announcer.
      final autoSeeder = AutoSeeder(
        transfers: coordinator.updates,
        seeding: seedingBloc,
        isEnabled: () => settingsCubit.state.autoSeedDownloads,
      )..start();

      online = OnlineServices(
        uid: uid,
        manager: manager,
        coordinator: coordinator,
        announcer: announcer,
        autoSeeder: autoSeeder,
        catalogBloc: NetworkCatalogBloc(repository: tracker, selfUid: uid),
        transfersBloc: TransfersBloc(coordinator),
      );

      return true;
    } catch (e, stackTrace) {
      debugPrint('[APP] Нет связи с Firebase: $e');
      debugPrint('$stackTrace');
      return false;
    }
  }

  /// Файл, который можно раздавать прямо сейчас (на месте и не изменён).
  SeedFile? _lookupSeed(String fileId) {
    for (final entry in seedingBloc.state.seeds) {
      if (entry.canSeed && entry.file.id == fileId) return entry.file;
    }
    return null;
  }

  /// Папка для скачанных файлов: Документы\Peerlink.
  Future<Directory> _downloadsDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory(p.join(documents.path, 'Peerlink'));
  }

  /// Вызывается при закрытии приложения.
  Future<void> shutdown() async {
    await online?.shutdown();
  }
}
