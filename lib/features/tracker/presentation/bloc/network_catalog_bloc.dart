import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:p2pchat/features/tracker/data/models/network_file.dart';
import 'package:p2pchat/features/tracker/data/models/peer_announcement.dart';
import 'package:p2pchat/features/tracker/data/repositories/tracker_repository.dart';

part 'network_catalog_event.dart';
part 'network_catalog_state.dart';

/// Каталог "Available Network Files".
///
/// Слушает анонсы пиров в Firestore, пока открыта вкладка, и собирает из них
/// список файлов с числом раздающих.
class NetworkCatalogBloc
    extends Bloc<NetworkCatalogEvent, NetworkCatalogState> {
  final TrackerRepository _repository;
  final String _selfUid;

  /// Пир считается онлайн, если его последний heartbeat не старше этого
  /// времени. Должен быть заметно больше SeedAnnouncer.heartbeatInterval,
  /// с запасом на расхождение часов клиентов и сервера.
  final Duration peerTtl;

  StreamSubscription<List<PeerAnnouncement>>? _subscription;
  Timer? _tickTimer;
  List<PeerAnnouncement> _peers = const [];

  NetworkCatalogBloc({
    required this._repository,
    required this._selfUid,
    this.peerTtl = const Duration(minutes: 5),
  }) : super(const NetworkCatalogState()) {
    on<StartWatchingCatalog>(_onStart);
    on<StopWatchingCatalog>(_onStop);
    on<_PeersUpdated>(_onPeersUpdated);
    on<_CatalogTick>(_onTick);
    on<_CatalogFailed>(_onFailed);
  }

  void _onStart(StartWatchingCatalog event, Emitter<NetworkCatalogState> emit) {
    // Повторное открытие вкладки: начинаем с чистой подписки, чтобы
    // временное окно запроса (discoveryWindow) пересчиталось.
    _subscription?.cancel();
    _tickTimer?.cancel();

    emit(state.copyWith(status: CatalogStatus.loading, clearError: true));

    _subscription = _repository.watchPeers().listen(
      (peers) => add(_PeersUpdated(peers)),
      onError: (Object error) => add(_CatalogFailed(error.toString())),
    );

    _tickTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => add(const _CatalogTick()),
    );
  }

  void _onStop(StopWatchingCatalog event, Emitter<NetworkCatalogState> emit) {
    _stopWatching();
    _peers = const [];

    emit(const NetworkCatalogState());
  }

  void _onPeersUpdated(_PeersUpdated event, Emitter<NetworkCatalogState> emit) {
    _peers = event.peers;
    _rebuild(emit);
  }

  void _onTick(_CatalogTick event, Emitter<NetworkCatalogState> emit) {
    if (state.status == CatalogStatus.ready) {
      _rebuild(emit);
    }
  }

  void _onFailed(_CatalogFailed event, Emitter<NetworkCatalogState> emit) {
    emit(state.copyWith(status: CatalogStatus.error, error: event.message));
  }

  void _rebuild(Emitter<NetworkCatalogState> emit) {
    final files = buildCatalog(
      peers: _peers,
      selfUid: _selfUid,
      now: DateTime.now(),
      ttl: peerTtl,
    );

    emit(
      state.copyWith(
        status: CatalogStatus.ready,
        files: files,
        clearError: true,
      ),
    );
  }

  void _stopWatching() {
    _subscription?.cancel();
    _subscription = null;
    _tickTimer?.cancel();
    _tickTimer = null;
  }

  @override
  Future<void> close() {
    _stopWatching();
    return super.close();
  }
}
