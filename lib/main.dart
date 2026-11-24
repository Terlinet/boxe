import 'package:flutter/material.dart';

import 'dart:math' as math;

import 'fight_screen.dart';

void main() {
  runApp(const BoxerApp());
}

class BoxerApp extends StatelessWidget {
  const BoxerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Boxer Cyberpunk',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const BoxerHomePage(),
    );
  }
}

class BoxerHomePage extends StatefulWidget {
  const BoxerHomePage({super.key});

  @override
  State<BoxerHomePage> createState() => _BoxerHomePageState();
}

class _BoxerHomePageState extends State<BoxerHomePage>
    with TickerProviderStateMixin {
  late AnimationController _murmurationController;
  late AnimationController _pulseController;

  final List<BirdFlock> _flocks = List.generate(6, (index) => BirdFlock(index));

  @override
  void initState() {
    super.initState();
    _murmurationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _murmurationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // 1. GIF de fundo (pepesoco.gif) ocupando toda a tela (enquadramento original)
          Positioned.fill(
            child: Image.asset('assets/gifs/pepesoco.gif', fit: BoxFit.cover),
          ),

          // 2. Camada escura com contraste suave
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.50),
                    Colors.black.withOpacity(0.25),
                    Colors.black.withOpacity(0.70),
                  ],
                ),
              ),
            ),
          ),

          // Linhas de Scanline Cyberpunk
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: CyberGridPainter()),
            ),
          ),

          // 3. Logo TerlineT no Canto Superior Esquerdo (sem plano de fundo)
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 12.0, left: 16.0),
                child: _buildTerlineTLogo(),
              ),
            ),
          ),

          // 4. Centro da Tela: Elemento Boxer Cyberpunk
          Positioned.fill(
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 70), // espaço para o header/logo
                        _buildCyberpunkBoxerCore(),
                        const SizedBox(height: 40),
                        _buildActionButtons(),
                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Logo TerlineT no canto superior esquerdo totalmente sem plano de fundo
  Widget _buildTerlineTLogo() {
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedBuilder(
          animation: _murmurationController,
          builder: (context, child) => CustomPaint(
            painter: MurmurationPainter(_flocks, _murmurationController.value),
            size: const Size(190, 44),
          ),
        ),
        const Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'T',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w100,
                color: Colors.white,
                letterSpacing: 1.2,
                shadows: [
                  Shadow(
                    blurRadius: 10.0,
                    color: Color(0xFF00FFE0),
                    offset: Offset(0, 0),
                  ),
                ],
              ),
            ),
            SizedBox(width: 4),
            Text(
              'E R L I N E',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w300,
                color: Colors.white70,
                letterSpacing: 4.5,
                shadows: [
                  Shadow(
                    blurRadius: 8.0,
                    color: Color(0xFF00FFE0),
                    offset: Offset(0, 0),
                  ),
                ],
              ),
            ),
            SizedBox(width: 4),
            Text(
              'T',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w100,
                color: Colors.white,
                letterSpacing: 1.2,
                shadows: [
                  Shadow(
                    blurRadius: 10.0,
                    color: Color(0xFF00FFE0),
                    offset: Offset(0, 0),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Painel Central Boxer Estilo Cyberpunk (Totalmente transparente, sem planos de fundo)
  Widget _buildCyberpunkBoxerCore() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulse = _pulseController.value;
        return Container(
          constraints: const BoxConstraints(maxWidth: 440),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            children: [
              // Tag de Status Cyberpunk (sem fundo)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'SYS // BXR-2077',
                    style: TextStyle(
                      color: Color(0xFF00FFE0),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.0,
                      shadows: [
                        Shadow(blurRadius: 8.0, color: Color(0xFF00FFE0)),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF00FF66),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00FF66).withOpacity(0.9),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'COMBAT READY',
                        style: TextStyle(
                          color: Color(0xFF00FF66),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          shadows: [
                            Shadow(blurRadius: 8.0, color: Color(0xFF00FF66)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Título BOXER em Neon
              ShaderMask(
                shaderCallback: (bounds) {
                  return LinearGradient(
                    colors: [
                      Color.lerp(
                        const Color(0xFF00FFE0),
                        const Color(0xFFFF0077),
                        pulse,
                      )!,
                      Colors.white,
                      Color.lerp(
                        const Color(0xFFFF0077),
                        const Color(0xFF00FFE0),
                        pulse,
                      )!,
                    ],
                  ).createShader(bounds);
                },
                child: const Text(
                  'B O X E R',
                  style: TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 12,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        blurRadius: 20.0,
                        color: Color(0xFF00FFE0),
                        offset: Offset(0, 0),
                      ),
                      Shadow(
                        blurRadius: 30.0,
                        color: Color(0xFFFF0077),
                        offset: Offset(0, 0),
                      ),
                    ],
                  ),
                ),
              ),

              const Text(
                'ARCADE BOXING // FIRST PERSON',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 4.5,
                  color: Color(0xFFFFCC00),
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(blurRadius: 10.0, color: Color(0xFFFFCC00))],
                ),
              ),

              const SizedBox(height: 28),

              const Text(
                'ESQUIVE COM A CABEÇA  •  SOQUE COM OS BRAÇOS',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF00FFE0),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Botão para iniciar uma luta controlada por gestos.
  Widget _buildActionButtons() {
    return GestureDetector(
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const FightScreen())),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 17),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF00FFE0), Color(0xFF007A88)],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFCC00), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00FFE0).withOpacity(0.55),
              blurRadius: 22,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sports_mma, color: Colors.black, size: 22),
            SizedBox(width: 10),
            Text(
              'INICIAR LUTA',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w900,
                fontSize: 15,
                letterSpacing: 1.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Linhas de Grade e HUD Cyberpunk
class CyberGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00FFE0).withOpacity(0.04)
      ..strokeWidth = 1.0;

    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Identidade Visual Murmuration de Pássaros/Partículas do TerlineT
class BirdFlock {
  final int id;
  BirdFlock(this.id);
}

class MurmurationPainter extends CustomPainter {
  final List<BirdFlock> flocks;
  final double animationValue;

  MurmurationPainter(this.flocks, this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final double t = DateTime.now().millisecondsSinceEpoch / 2500.0;
    for (int i = 0; i < 45; i++) {
      final pos =
          center +
          Offset(math.sin(t + i * 0.4) * 85, math.cos(t * 0.4 + i * 0.6) * 18);
      canvas.drawCircle(
        pos,
        1.1,
        Paint()
          ..color = const Color(0xFF00FFE0)
              .withOpacity(0.20 + (math.sin(t + i).abs() * 0.35)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant MurmurationPainter oldDelegate) => true;
}
