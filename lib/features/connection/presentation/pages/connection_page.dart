/*import 'dart:convert';

import 'package:flutter/material.dart' hide ConnectionState;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:p2pchat/features/connection/presentation/bloc/web_rtc_status.dart';
import 'package:p2pchat/features/file_exchange/presentation/pages/file_exchange_page.dart';
import 'package:p2pchat/features/connection/presentation/bloc/connection_bloc.dart';

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key});

  @override
  State<ConnectionPage> createState() => _HomePageState();
}

class _HomePageState extends State<ConnectionPage> {
  final TextEditingController _textEditingController = TextEditingController();

  final TextEditingController _peerIdController = TextEditingController(
    text: 'manual',
  );

  String _peerId = 'manual';

  @override
  void dispose() {
    _textEditingController.dispose();
    _peerIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        // Листенер статуса подключения
        BlocListener<ConnectionBloc, ConnectionState>(
          listenWhen: (previous, current) =>
              previous.peer(_peerId).status != current.peer(_peerId).status &&
              current.peer(_peerId).status == WebRTCStatus.connected,
          listener: (context, state) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => FileExchangePage(peerId: _peerId),
              ),
            );
          },
        ),

        BlocListener<ConnectionBloc, ConnectionState>(
          listenWhen: (previous, current) {
            final oldPeer = previous.peer(_peerId);
            final newPeer = current.peer(_peerId);

            return oldPeer.localDescription != newPeer.localDescription &&
                newPeer.localDescription != null &&
                newPeer.remoteDescription == null;
          },
          listener: (context, state) async {
            await Clipboard.setData(
              ClipboardData(text: state.peer(_peerId).localDescription!),
            );
            if (!context.mounted) return;

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Offer скопирован в буфер!')),
            );
          },
        ),

        BlocListener<ConnectionBloc, ConnectionState>(
          listenWhen: (previous, current) {
            final oldPeer = previous.peer(_peerId);
            final newPeer = current.peer(_peerId);

            return oldPeer.localDescription != newPeer.localDescription &&
                newPeer.localDescription != null &&
                newPeer.remoteDescription != null;
          },
          listener: (context, state) async {
            await Clipboard.setData(
              ClipboardData(text: state.peer(_peerId).localDescription!),
            );

            if (!context.mounted) return;

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Answer скопирован в буфер!')),
            );
          },
        ),
      ],
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6FF),
        body: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'P2P File Exchange',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF303B72),
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      'WebRTC connection',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Color(0xFF747CA5)),
                    ),

                    const SizedBox(height: 36),

                    TextField(
                      controller: _peerIdController,
                      onChanged: (value) {
                        setState(() {
                          _peerId = value.trim();
                        });
                      },
                      decoration: InputDecoration(
                        labelText: 'Peer ID',
                        prefixIcon: const Icon(Icons.devices_rounded),
                        filled: true,
                        fillColor: const Color(0xFFF7F7FC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFFE2E4F2),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF5C6BC0)
                                .withValues(alpha: 0.10),
                            blurRadius: 25,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Подключение',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF303B72),
                            ),
                          ),

                          const SizedBox(height: 20),

                          Row(
                            children: [
                              SetAnswerButton(
                                peerId: _peerId,
                                textEditingController: _textEditingController,
                              ),

                              const SizedBox(width: 12),

                              CreateOfferButton(peerId: _peerId),

                              const SizedBox(width: 12),

                              CreateAnswerButton(
                                peerId: _peerId,
                                textEditingController: _textEditingController,
                              ),
                            ],
                          ),

                          const SizedBox(height: 28),

                          const Text(
                            'Offer / Answer',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF454D78),
                            ),
                          ),

                          const SizedBox(height: 10),

                          ParametersOfWebRTCTextField(
                            textEditingController: _textEditingController,
                          ),

                          const SizedBox(height: 12),

                          _AddIceButton(
                            controller: _textEditingController,
                            peerId: _peerId,
                          ),

                          const SizedBox(height: 28),

                          const Text(
                            'Локальные ICE Candidates',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF454D78),
                            ),
                          ),

                          const SizedBox(height: 10),

                          LocalIceCandidatesField(peerId: _peerId),

                          const SizedBox(height: 12),

                          CopyLocalIceCandidatesButton(peerId: _peerId),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECEEFF),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFD8DCF6)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.terminal_rounded,
                            color: Color(0xFF6874C5),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Логи',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF3F4778),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                LogText(peerId: _peerId),
                              ],
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
        ),
      ),
    );
  }
}

class CreateAnswerButton extends StatelessWidget {
  const new({
    super.key,
    required this._peerId,
    required this._textEditingController,
  });

  final String _peerId;
  final TextEditingController _textEditingController;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: _ActionButton(
        title: 'Create Answer',
        icon: Icons.download_rounded,
        onPressed: () {
          if (_peerId.isEmpty) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Укажи Peer ID')));
            return;
          }

          final offerJson = _textEditingController.text.trim();

          if (offerJson.isEmpty) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Вставь Offer')));
            return;
          }

          context.read<ConnectionBloc>().add(
            CreateAnswer(peerId: _peerId, offerJson: offerJson),
          );
        },
      ),
    );
  }
}

class CreateOfferButton extends StatelessWidget {
  const new({super.key, required this._peerId});

  final String _peerId;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: _ActionButton(
        title: 'Create Offer',
        icon: Icons.upload_rounded,
        onPressed: () {
          if (_peerId.isEmpty) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Укажи Peer ID')));
            return;
          }

          context.read<ConnectionBloc>().add(CreateOffer(peerId: _peerId));
        },
      ),
    );
  }
}

class SetAnswerButton extends StatelessWidget {
  const new({
    super.key,
    required this._peerId,
    required this._textEditingController,
  });

  final String _peerId;
  final TextEditingController _textEditingController;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: _ActionButton(
        title: 'Set Answer',
        icon: Icons.add_link_rounded,
        onPressed: () {
          if (_peerId.isEmpty) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Укажи Peer ID')));
            return;
          }

          final answerJson = _textEditingController.text.trim();

          if (answerJson.isEmpty) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Вставь Answer')));
            return;
          }

          context.read<ConnectionBloc>().add(
            SetAnswer(peerId: _peerId, answerJson: answerJson),
          );
        },
      ),
    );
  }
}

class _AddIceButton extends StatelessWidget {
  final TextEditingController controller;
  final String peerId;

  const _AddIceButton({required this.controller, required this.peerId});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () {
        if (peerId.isEmpty) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Укажи Peer ID')));
          return;
        }

        final candidatesJson = controller.text.trim();

        if (candidatesJson.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Вставь JSON с ICE Candidates')),
          );
          return;
        }

        context.read<ConnectionBloc>().add(
          AddIceCandidates(peerId: peerId, candidatesJson: candidatesJson),
        );
      },
      icon: const Icon(Icons.add_link_rounded),
      label: const Text('Добавить ICE Candidates'),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF5966B8),
        side: const BorderSide(color: Color(0xFFBBC0E5)),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class CopyLocalIceCandidatesButton extends StatelessWidget {
  final String peerId;

  const CopyLocalIceCandidatesButton({super.key, required this.peerId});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectionBloc, ConnectionState>(
      builder: (context, state) {
        final enabled = state.peer(peerId).localCandidates.isNotEmpty;

        return OutlinedButton.icon(
          onPressed: enabled
              ? () async {
                  final candidates = state.peer(peerId).localCandidates;

                  final candidatesJson = jsonEncode(
                    candidates.map((candidate) => candidate.toMap()).toList(),
                  );

                  await Clipboard.setData(ClipboardData(text: candidatesJson));

                  if (!context.mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('ICE Candidates скопированы!'),
                    ),
                  );
                }
              : null,
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Скопировать ICE Candidates'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF5966B8),
            side: const BorderSide(color: Color(0xFFBBC0E5)),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      },
    );
  }
}

class LocalIceCandidatesField extends StatelessWidget {
  final String peerId;

  const LocalIceCandidatesField({super.key, required this.peerId});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectionBloc, ConnectionState>(
      builder: (context, state) {
        final candidates = state.peer(peerId).localCandidates;

        final candidatesJson = jsonEncode(
          candidates.map((candidate) => candidate.toMap()).toList(),
        );

        return TextFormField(
          key: ValueKey(peerId),
          initialValue: candidates.isEmpty ? '' : candidatesJson,
          readOnly: true,
          maxLines: 8,
          decoration: InputDecoration(
            hintText: 'Ожидание ICE candidates...',
            filled: true,
            fillColor: const Color(0xFFF7F7FC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE2E4F2)),
            ),
          ),
        );
      },
    );
  }
}

class ParametersOfWebRTCTextField extends StatelessWidget {
  const new({super.key, required this._textEditingController});

  final TextEditingController _textEditingController;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _textEditingController,
      maxLines: 8,
      decoration: InputDecoration(
        hintText: 'Вставьте сюда Offer / Answer / ICE Candidates...',
        hintStyle: const TextStyle(color: Color(0xFFA0A6C0)),
        filled: true,
        fillColor: const Color(0xFFF7F7FC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E4F2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF6976C8), width: 1.5),
        ),
      ),
    );
  }
}

class LogText extends StatelessWidget {
  final String peerId;

  const LogText({super.key, required this.peerId});

  @override
  Widget build(BuildContext context) {
    final status = context.select(
      (ConnectionBloc bloc) => bloc.state.peer(peerId).status,
    );

    final error = context.select(
      (ConnectionBloc bloc) => bloc.state.peer(peerId).error,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Peer: $peerId', style: const TextStyle(color: Color(0xFF737A9D))),
        const SizedBox(height: 4),
        Text(
          'Статус: ${status.name}',
          style: const TextStyle(color: Color(0xFF737A9D)),
        ),
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(error, style: const TextStyle(color: Colors.red)),
        ],
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.title,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(title),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF6572C4),
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
*/
