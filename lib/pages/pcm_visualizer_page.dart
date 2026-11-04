import 'dart:async';

import 'package:flutter/material.dart';

import '../services/native_audio_features.dart';

class PcmVisualizerPage extends StatefulWidget {
  const PcmVisualizerPage({super.key});

  @override
  State<PcmVisualizerPage> createState() => _PcmVisualizerPageState();
}

class _PcmVisualizerPageState extends State<PcmVisualizerPage> {
  StreamSubscription<List<double>>? _subscription;
  List<double> _bars = const <double>[];
  bool _nativeSourceActive = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subscription = NativeAudioFeatures.waveform.listen(
      (bars) {
        if (!mounted || bars.isEmpty) return;
        setState(() => _bars = bars);
      },
      onError: (Object error) {
        if (mounted) setState(() => _error = error.toString());
      },
    );
    unawaited(_enable());
  }

  Future<void> _enable() async {
    final result = await NativeAudioFeatures.setVisualizerEnabled(true);
    if (!mounted) return;
    setState(() {
      _nativeSourceActive = result['nativeSourceActive'] == true;
      _error = result['error']?.toString();
    });
  }

  @override
  void dispose() {
    unawaited(NativeAudioFeatures.setVisualizerEnabled(false));
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('PCM Visualizer')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Container(
              height: 250,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: .55)),
              ),
              padding: const EdgeInsets.all(20),
              child: CustomPaint(
                painter: _PcmBarsPainter(_bars, scheme.primary, scheme.secondary),
                child: const SizedBox.expand(),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _error ?? (_nativeSourceActive
                  ? (_bars.isEmpty ? 'Menunggu data PCM dari player…' : 'Visualizer aktif · mengambil sampel PCM langsung')
                  : 'Visualizer membutuhkan pemutar native Media3. Putar file lokal atau stream audio native; fallback iframe YouTube tidak menyediakan PCM.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _enable,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Hubungkan ulang visualizer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PcmBarsPainter extends CustomPainter {
  const _PcmBarsPainter(this.values, this.primary, this.secondary);
  final List<double> values;
  final Color primary;
  final Color secondary;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) {
      final paint = Paint()
        ..color = primary.withValues(alpha: .22)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 28; i++) {
        final x = (i + .5) * size.width / 28;
        canvas.drawLine(Offset(x, size.height * .5 - 3), Offset(x, size.height * .5 + 3), paint);
      }
      return;
    }
    final gap = 3.0;
    final barWidth = (size.width - gap * (values.length - 1)) / values.length;
    for (var i = 0; i < values.length; i++) {
      final value = values[i].clamp(0.04, 1.0);
      final height = (size.height * .88 * value).clamp(5.0, size.height * .88);
      final left = i * (barWidth + gap);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, (size.height - height) / 2, barWidth, height),
        const Radius.circular(6),
      );
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [primary, secondary],
        ).createShader(rect.outerRect);
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PcmBarsPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.primary != primary || oldDelegate.secondary != secondary;
}
