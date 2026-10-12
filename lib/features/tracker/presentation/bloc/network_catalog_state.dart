part of 'network_catalog_bloc.dart';

enum CatalogStatus {
  /// Подписка не активна (вкладка закрыта).
  idle,

  /// Подписались, ждём первый снимок.
  loading,

  /// Каталог актуален.
  ready,

  /// Не удалось получить данные (нет сети, нет прав и т. п.).
  error,
}

class NetworkCatalogState extends Equatable {
  final CatalogStatus status;
  final List<NetworkFile> files;
  final String? error;

  const NetworkCatalogState({
    this.status = CatalogStatus.idle,
    this.files = const [],
    this.error,
  });

  NetworkCatalogState copyWith({
    CatalogStatus? status,
    List<NetworkFile>? files,
    String? error,
    bool clearError = false,
  }) {
    return NetworkCatalogState(
      status: status ?? this.status,
      files: files ?? this.files,
      error: clearError ? null : error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [status, files, error];
}
