import 'package:flutter/material.dart';
import 'package:p2pchat/features/file_exchange/presentation/theme/app_theme.dart';
import 'package:p2pchat/features/file_exchange/presentation/utils/formatters.dart';

enum HomeTab { discover, transfers, seeding }

/// Состояние подключения к сети (Firebase + WebRTC).
enum NetworkStatus { connecting, online, offline }

// -----------------------------------------------------------------------------
// Боковая панель
// -----------------------------------------------------------------------------

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.compact,
    required this.selected,
    required this.badges,
    required this.downSpeed,
    required this.upSpeed,
    required this.status,
    required this.onSelect,
  });

  final bool compact;
  final HomeTab selected;

  /// Число в бейдже вкладки; вкладки без записи показываются без бейджа.
  final Map<HomeTab, int> badges;
  final double downSpeed;
  final double upSpeed;
  final NetworkStatus status;
  final ValueChanged<HomeTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final width = compact ? 76.0 : 248.0;

    final (statusLabel, statusColor) = switch (status) {
      NetworkStatus.online => ('Connected', AppColors.success),
      NetworkStatus.connecting => ('Connecting…', AppColors.accent),
      NetworkStatus.offline => ('Offline', AppColors.danger),
    };

    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 14,
        20,
        compact ? 10 : 14,
        16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 8),
            child: Row(
              mainAxisAlignment: compact
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.hub_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 12),
                  const Text(
                    'Peerlink',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 28),
          NavItem(
            compact: compact,
            icon: Icons.travel_explore_rounded,
            label: 'Available network files',
            badge: badges[HomeTab.discover],
            selected: selected == HomeTab.discover,
            onTap: () => onSelect(HomeTab.discover),
          ),
          const SizedBox(height: 4),
          NavItem(
            compact: compact,
            icon: Icons.swap_vert_rounded,
            label: 'Transfers',
            badge: badges[HomeTab.transfers],
            selected: selected == HomeTab.transfers,
            onTap: () => onSelect(HomeTab.transfers),
          ),
          const SizedBox(height: 4),
          NavItem(
            compact: compact,
            icon: Icons.cloud_upload_outlined,
            label: 'My seeding files',
            badge: badges[HomeTab.seeding],
            selected: selected == HomeTab.seeding,
            onTap: () => onSelect(HomeTab.seeding),
          ),
          const Spacer(),
          if (!compact)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.circle, size: 9, color: statusColor),
                      const SizedBox(width: 8),
                      Text(
                        statusLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SpeedLine(
                    icon: Icons.arrow_downward_rounded,
                    label: 'Down',
                    value: formatSpeed(downSpeed),
                  ),
                  const SizedBox(height: 6),
                  _SpeedLine(
                    icon: Icons.arrow_upward_rounded,
                    label: 'Up',
                    value: formatSpeed(upSpeed),
                  ),
                ],
              ),
            )
          else
            Tooltip(
              message:
                  '$statusLabel\nDown ${formatSpeed(downSpeed)}\nUp ${formatSpeed(upSpeed)}',
              child: Icon(Icons.circle, size: 10, color: statusColor),
            ),
        ],
      ),
    );
  }
}

class _SpeedLine extends StatelessWidget {
  const _SpeedLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.accent),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class NavItem extends StatefulWidget {
  const NavItem({
    super.key,
    required this.compact,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final bool compact;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? badge;

  @override
  State<NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final bg = selected
        ? AppColors.sky
        : (_hovered ? AppColors.background : Colors.transparent);
    final fg = selected ? AppColors.primary : AppColors.text;
    final badge = widget.badge;

    final content = Row(
      mainAxisAlignment: widget.compact
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        Icon(
          widget.icon,
          size: 21,
          color: selected ? AppColors.primary : AppColors.muted,
        ),
        if (!widget.compact) ...[
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: fg,
              ),
            ),
          ),
          if (badge != null && badge > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.border,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$badge',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppColors.muted,
                ),
              ),
            ),
        ],
      ],
    );

    return Tooltip(
      message: widget.compact ? widget.label : '',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 44,
            padding: EdgeInsets.symmetric(horizontal: widget.compact ? 0 : 12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                if (selected)
                  Positioned(
                    left: widget.compact ? 0 : -12,
                    child: Container(
                      width: 3,
                      height: 20,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                SizedBox(width: double.infinity, child: content),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Каркас страницы
// -----------------------------------------------------------------------------

class TabScaffold extends StatelessWidget {
  const TabScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 14,
            spacing: 16,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 24),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: c, width: w),
    );

    return SizedBox(
      width: 320,
      height: 42,
      child: TextField(
        onChanged: onChanged,
        style: const TextStyle(fontSize: 14, color: AppColors.text),
        decoration: InputDecoration(
          hintText: 'Search files on the network',
          hintStyle: const TextStyle(color: AppColors.muted),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 20,
            color: AppColors.muted,
          ),
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: EdgeInsets.zero,
          enabledBorder: border(AppColors.border),
          focusedBorder: border(AppColors.accent, 1.6),
          border: border(AppColors.border),
        ),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel({super.key, required this.text, required this.count});

  final String text;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(
            text,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: const TextStyle(fontSize: 14, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class InlineNote extends StatelessWidget {
  const InlineNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(text, style: const TextStyle(color: AppColors.muted)),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.sky,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted),
            ),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

/// Полоса над содержимым: нет связи с сетью или идёт подключение.
class NetworkBanner extends StatelessWidget {
  const NetworkBanner({super.key, required this.status, required this.onRetry});

  final NetworkStatus status;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (status == NetworkStatus.online) return const SizedBox.shrink();

    final connecting = status == NetworkStatus.connecting;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
      decoration: BoxDecoration(
        color: connecting ? AppColors.sky : AppColors.dangerBg,
        border: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (connecting)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const Icon(
              Icons.cloud_off_outlined,
              size: 18,
              color: AppColors.danger,
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              connecting
                  ? 'Подключение к сети…'
                  : 'Нет связи с сервером. Раздача и скачивание недоступны, '
                        'добавлять файлы в раздачу можно.',
              style: TextStyle(
                color: connecting ? AppColors.primary : AppColors.danger,
                fontSize: 13,
              ),
            ),
          ),
          if (!connecting)
            TextButton(onPressed: onRetry, child: const Text('Повторить')),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Карточка строки (используется всеми вкладками)
// -----------------------------------------------------------------------------

/// Карточка с наведением: иконка + название/подпись | метрики | действия и
/// необязательный [footer] (например, полоса прогресса). Ниже 780 px ширины
/// метрики переносятся под название.
class RowCard extends StatefulWidget {
  const RowCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.metrics,
    required this.actions,
    this.footer,
    this.subtitleColor = AppColors.muted,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color subtitleColor;
  final List<Widget> metrics;
  final List<Widget> actions;
  final Widget? footer;

  @override
  State<RowCard> createState() => _RowCardState();
}

class _RowCardState extends State<RowCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final head = Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.sky,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(widget.icon, color: AppColors.primary, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                widget.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: widget.subtitleColor),
              ),
            ],
          ),
        ),
      ],
    );

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: widget.actions,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _hovered ? AppColors.accent : AppColors.border,
          ),
          boxShadow: _hovered
              ? const [
                  BoxShadow(
                    color: Color(0x1A1565C0),
                    blurRadius: 14,
                    offset: Offset(0, 4),
                  ),
                ]
              : const [],
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 780;

            final Widget top = wide
                ? Row(
                    children: [
                      Expanded(flex: 3, child: head),
                      const SizedBox(width: 16),
                      ...widget.metrics,
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 170,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: actions,
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: head),
                          const SizedBox(width: 12),
                          actions,
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 28,
                        runSpacing: 10,
                        children: widget.metrics,
                      ),
                    ],
                  );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                top,
                if (widget.footer != null) ...[
                  const SizedBox(height: 14),
                  widget.footer!,
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Пара "подпись / значение". [customValue] позволяет показать виджет
/// (например, статус) вместо текста.
class Metric extends StatelessWidget {
  const Metric({
    super.key,
    required this.label,
    this.value,
    this.icon,
    this.customValue,
    this.width = 108,
  });

  final String label;
  final String? value;
  final IconData? icon;
  final Widget? customValue;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 4),
          customValue ??
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 14, color: AppColors.accent),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(
                      value ?? '',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                ],
              ),
        ],
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    required this.background,
    required this.icon,
  });

  final String label;
  final Color color;
  final Color background;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Полоса прогресса. [value] == null даёт неопределённую анимацию
/// (подключение, проверка хеша).
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({super.key, required this.value, this.paused = false});

  final double? value;

  /// Приостановленная загрузка рисуется серым.
  final bool paused;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 8,
        backgroundColor: AppColors.sky,
        valueColor: AlwaysStoppedAnimation<Color>(
          paused ? AppColors.muted : AppColors.accent,
        ),
      ),
    );
  }
}
