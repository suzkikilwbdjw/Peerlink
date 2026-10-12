import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:p2pchat/features/settings/data/repositories/settings_repository.dart';

class SettingsState extends Equatable {
  /// Раздавать скачанные файлы автоматически.
  final bool autoSeedDownloads;

  const SettingsState({this.autoSeedDownloads = true});

  SettingsState copyWith({bool? autoSeedDownloads}) {
    return SettingsState(
      autoSeedDownloads: autoSeedDownloads ?? this.autoSeedDownloads,
    );
  }

  @override
  List<Object?> get props => [autoSeedDownloads];
}

class SettingsCubit extends Cubit<SettingsState> {
  final SettingsRepository _repository;

  SettingsCubit(SettingsRepository repository)
    : _repository = repository,
      super(SettingsState(autoSeedDownloads: repository.autoSeedDownloads));

  Future<void> setAutoSeedDownloads(bool value) async {
    // Сначала обновляем интерфейс, потом сохраняем.
    emit(state.copyWith(autoSeedDownloads: value));
    await _repository.setAutoSeedDownloads(value);
  }
}
