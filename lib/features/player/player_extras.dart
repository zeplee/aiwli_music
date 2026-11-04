import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../core/models/quality.dart';
import '../../core/services/app_settings.dart';
import '../../player/models.dart';
import '../../player/providers.dart';

/// 音质档位选择（底部弹层）。
Future<void> showQualitySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => const _QualitySheet(),
  );
}

class _QualitySheet extends ConsumerWidget {
  const _QualitySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
            padding: const EdgeInsets.all(14),
            child: Text('音质档位（脚本支持时生效）',
                style: Theme.of(context).textTheme.titleMedium)),
        RadioGroup<Quality>(
          groupValue: settings.quality,
          onChanged: (v) {
            if (v != null) ref.read(appSettingsProvider).setQuality(v);
          },
          child: Column(
            children: [
              for (final q in Quality.values)
                RadioListTile<Quality>(
                  value: q,
                  title: Text(q.label),
                  activeColor: scheme.primary,
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ]),
    );
  }
}

/// 定时关闭（底部弹层）。
Future<void> showSleepTimerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => const _SleepSheet(),
  );
}

class _SleepSheet extends ConsumerWidget {
  const _SleepSheet();

  static const _presets = [15, 30, 45, 60, 90];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(sleepTimerProvider);
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ListenableBuilder(
        listenable: timer,
        builder: (context, _) => Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
              padding: const EdgeInsets.all(14),
              child: Text('定时关闭',
                  style: Theme.of(context).textTheme.titleMedium)),
          if (timer.endsAt != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                  '剩余 ${timer.remaining.inMinutes} 分 ${timer.remaining.inSeconds.remainder(60)} 秒',
                  style: TextStyle(color: scheme.primary, fontSize: 15)),
            ),
          if (timer.endOfTrackActive)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('播完当前歌曲后暂停'),
            ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              for (final m in _presets)
                FilledButton.tonal(
                  onPressed: () {
                    ref
                        .read(sleepTimerProvider)
                        .startCountdown(Duration(minutes: m));
                  },
                  child: Text('$m 分钟'),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            OutlinedButton.icon(
              onPressed: () {
                ref.read(sleepTimerProvider).startEndOfTrack();
                if (context.mounted) Navigator.of(context).pop();
              },
              icon: const Icon(Icons.skip_next),
              label: const Text('播完当前首'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () {
                ref.read(sleepTimerProvider).cancel();
                if (context.mounted) Navigator.of(context).pop();
              },
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('取消定时'),
            ),
          ]),
          const SizedBox(height: 18),
        ]),
      ),
    );
  }
}

/// 均衡器（底部弹层）：预设 + 10 段自定义。
Future<void> showEqSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _EqSheet(),
  );
}

class EqPreset {
  const EqPreset(this.name, this.gains);
  final String name;
  final List<double> gains;
}

const eqPresets = <EqPreset>[
  EqPreset('平直', [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
  EqPreset('流行', [-1, 1, 2, 3, 3, 1, 0, -1, -1, -2]),
  EqPreset('摇滚', [4, 3, 1, 0, -1, 0, 1, 3, 4, 4]),
  EqPreset('爵士', [3, 2, 1, 2, -1, -1, 0, 1, 2, 3]),
  EqPreset('古典', [3, 2, 0, 0, 0, 0, -1, 1, 2, 3]),
  EqPreset('低音增强', [6, 5, 3, 1, 0, 0, 0, 0, 0, 0]),
  EqPreset('人声', [-2, -1, 0, 2, 3, 3, 2, 1, 0, -1]),
  EqPreset('高音增强', [0, 0, 0, 0, 0, 1, 2, 4, 5, 6]),
];

class _EqSheet extends ConsumerStatefulWidget {
  const _EqSheet();

  @override
  ConsumerState<_EqSheet> createState() => _EqSheetState();
}

class _EqSheetState extends ConsumerState<_EqSheet> {
  bool _localEnabled = false;
  List<double> _localGains = List.filled(AppSettings.eqBandHz.length, 0);

  @override
  void initState() {
    super.initState();
    final s = ref.read(appSettingsProvider);
    _localEnabled = s.eqEnabled;
    _localGains = [...s.eqGains];
    // 打开时同步引擎（覆盖冷启动场景）
    WidgetsBinding.instance.addPostFrameCallback((_) => _push());
  }

  Future<void> _push() async {
    await ref.read(engineProvider).setEqualizer(
          _localEnabled ? List<double>.from(_localGains) : null,
        );
  }

  Future<void> _persist() async {
    await ref
        .read(appSettingsProvider)
        .setEq(enabled: _localEnabled, gains: _localGains, preset: 'custom');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.62,
        child: Column(children: [
          SwitchListTile(
            title: const Text('均衡器'),
            subtitle: const Text('基于 mpv 10 段 peaking EQ'),
            value: _localEnabled,
            onChanged: (v) {
              setState(() => _localEnabled = v);
              _push();
              _persist();
            },
          ),
          if (!_localEnabled)
            Expanded(
              child: Center(
                child: Text('开启后可调节',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final p in eqPresets)
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12)),
                    onPressed: () {
                      setState(() {
                        _localGains = [...p.gains];
                      });
                      _push();
                      _persist();
                    },
                    child: Text(p.name, style: const TextStyle(fontSize: 13)),
                  ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    for (var i = 0; i < _localGains.length; i++)
                      Expanded(
                        child: Column(children: [
                          Expanded(
                            child: RotatedBox(
                              quarterTurns: -1,
                              child: Slider(
                                value: _localGains[i],
                                min: AppSettings.eqMinDb,
                                max: AppSettings.eqMaxDb,
                                onChanged: (v) =>
                                    setState(() => _localGains[i] = v),
                                onChangeEnd: (v) {
                                  _localGains[i] = v;
                                  _push();
                                  _persist();
                                },
                              ),
                            ),
                          ),
                          Text('${AppSettings.eqBandHz[i] >= 1000 ? '${AppSettings.eqBandHz[i] ~/ 1000}k' : AppSettings.eqBandHz[i]}',
                              style: const TextStyle(fontSize: 10)),
                          Text('${_localGains[i].round()}dB',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: scheme.onSurfaceVariant)),
                        ]),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
        ]),
      ),
    );
  }
}

/// 播放队列面板：当前曲高亮、点击跳播、左滑移除。
Future<void> showQueueSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _QueueSheet(),
  );
}

class _QueueSheet extends ConsumerWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final core = ref.watch(playerCoreProvider);
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<PlayerUiState>(
      valueListenable: core.state,
      builder: (context, s, _) {
        final queue = core.queue;
        final currentIndex = core.currentIndex;
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.62,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                child: Row(children: [
                  Text('播放队列 · ${queue.length} 首',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    tooltip: '清空',
                    onPressed: queue.isEmpty
                        ? null
                        : () async {
                            for (var i = queue.length - 1; i >= 0; i--) {
                              await core.removeAt(i);
                            }
                          },
                    icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                  ),
                ]),
              ),
              const Divider(height: 1),
              Expanded(
                child: queue.isEmpty
                    ? const Center(child: Text('队列为空'))
                    : ListView.builder(
                        itemCount: queue.length,
                        itemBuilder: (context, i) {
                          final it = queue[i];
                          final active = i == currentIndex;
                          return Dismissible(
                            key: ValueKey('queue_${it.sourceId}_${it.musicId}_$i'),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: scheme.errorContainer,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child: Icon(Icons.delete_outline,
                                  color: scheme.onErrorContainer),
                            ),
                            onDismissed: (_) => core.removeAt(i),
                            child: ListTile(
                              dense: true,
                              leading: Icon(
                                active
                                    ? Icons.graphic_eq
                                    : Icons.music_note_outlined,
                                color: active
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                                size: 20,
                              ),
                              title: Text(
                                it.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: active ? scheme.primary : null,
                                  fontWeight:
                                      active ? FontWeight.bold : null,
                                ),
                              ),
                              subtitle: Text(it.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12)),
                              onTap: () => core.playAt(i),
                            ),
                          );
                        },
                      ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

/// 倍速选择（0.5x – 2.0x）。
Future<void> showSpeedSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => const _SpeedSheet(),
  );
}

class _SpeedSheet extends ConsumerWidget {
  const _SpeedSheet();

  static const _rates = <double>[0.5, 0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final core = ref.watch(playerCoreProvider);
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<PlayerUiState>(
      valueListenable: core.state,
      builder: (context, s, _) {
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text('播放速度',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in _rates)
                  ChoiceChip(
                    label: Text('${r}x'),
                    selected: (s.speed - r).abs() < 0.001,
                    selectedColor: scheme.primaryContainer,
                    onSelected: (_) {
                      core.setSpeed(r);
                      Navigator.of(context).maybePop();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ]),
        );
      },
    );
  }
}
