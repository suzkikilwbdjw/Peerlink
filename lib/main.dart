import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:p2pchat/app_services.dart';
import 'package:p2pchat/features/file_exchange/presentation/pages/home_page.dart';
import 'package:p2pchat/features/file_exchange/presentation/theme/app_theme.dart';
import 'package:p2pchat/features/file_exchange/presentation/widgets/common_widgets.dart'
    show NetworkStatus;

import 'package:p2pchat/features/seeding/presentation/bloc/seeding_bloc.dart';
import 'package:p2pchat/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:p2pchat/features/tracker/presentation/bloc/network_catalog_bloc.dart';
import 'package:p2pchat/features/transfer/presentation/bloc/transfers_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await dotenv.load(fileName: '.env');

  final prefs = await SharedPreferences.getInstance();

  runApp(P2PApp(services: AppServices(prefs: prefs)));
}

class P2PApp extends StatefulWidget {
  const P2PApp({super.key, required this.services});

  final AppServices services;

  @override
  State<P2PApp> createState() => _P2PAppState();
}

class _P2PAppState extends State<P2PApp> {
  NetworkStatus _status = NetworkStatus.connecting;
  late final AppLifecycleListener _lifecycle;

  bool _isExiting = false;

  @override
  void initState() {
    super.initState();

    _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
    _connect();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_status == NetworkStatus.online) return;

    setState(() => _status = NetworkStatus.connecting);

    final ok = await widget.services.goOnline();
    if (!mounted) return;

    setState(() => _status = ok ? NetworkStatus.online : NetworkStatus.offline);
  }

  Future<AppExitResponse> _onExitRequested() async {
    setState(() {
      _isExiting = true;
    });

    try {
      await widget.services.shutdown().timeout(const Duration(seconds: 3));
    } catch (_) {}
    return AppExitResponse.exit;
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    final online = services.online;

    return RepositoryProvider<AppServices>.value(
      value: services,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<SeedingBloc>.value(value: services.seedingBloc),
          BlocProvider<SettingsCubit>.value(value: services.settingsCubit),
          if (online != null) ...[
            BlocProvider<NetworkCatalogBloc>.value(value: online.catalogBloc),
            BlocProvider<TransfersBloc>.value(value: online.transfersBloc),
          ],
        ],
        child: MaterialApp(
          title: 'Peerlink',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: Scaffold(
            body: Stack(
              children: [
                HomeScreen(status: _status, onRetry: _connect),

                if (_isExiting)
                  Positioned.fill(
                    child: Container(
                      color: AppColors.text.withValues(alpha: 0.6),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.accent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
