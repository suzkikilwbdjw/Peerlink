part of 'network_catalog_bloc.dart';

abstract class NetworkCatalogEvent extends Equatable {
  const NetworkCatalogEvent();

  @override
  List<Object?> get props => [];
}

/// Начать слушать сеть. Отправляйте, когда открывается вкладка
/// "Available Network Files".
class StartWatchingCatalog extends NetworkCatalogEvent {
  const StartWatchingCatalog();
}

/// Перестать слушать сеть. Отправляйте при уходе с вкладки: пока подписка
/// активна, каждый heartbeat любого пира тратит чтения Firestore.
class StopWatchingCatalog extends NetworkCatalogEvent {
  const StopWatchingCatalog();
}

class _PeersUpdated extends NetworkCatalogEvent {
  final List<PeerAnnouncement> peers;

  const _PeersUpdated(this.peers);

  @override
  List<Object?> get props => [peers];
}

/// Периодический пересчёт каталога: пир мог "протухнуть" по TTL, хотя
/// новых снимков из Firestore не приходило.
class _CatalogTick extends NetworkCatalogEvent {
  const _CatalogTick();
}

class _CatalogFailed extends NetworkCatalogEvent {
  final String message;

  const _CatalogFailed(this.message);

  @override
  List<Object?> get props => [message];
}
