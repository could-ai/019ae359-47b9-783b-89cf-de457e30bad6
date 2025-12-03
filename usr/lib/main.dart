import 'dart:async';
import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/parallax.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ==========================================
// 1. MAIN ENTRY POINT & APP STRUCTURE
// ==========================================

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Set full screen and landscape/portrait
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const SkyJumpApp());
}

class SkyJumpApp extends StatelessWidget {
  const SkyJumpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sky Jump Legends',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
        textTheme: GoogleFonts.cairoTextTheme(), // Arabic friendly font
      ),
      home: const GameContainer(),
    );
  }
}

// ==========================================
// 2. GAME CONTAINER & UI OVERLAYS
// ==========================================

class GameContainer extends StatefulWidget {
  const GameContainer({super.key});

  @override
  State<GameContainer> createState() => _GameContainerState();
}

class _GameContainerState extends State<GameContainer> {
  late SkyJumpGame _game;

  @override
  void initState() {
    super.initState();
    _game = SkyJumpGame();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GameWidget(
        game: _game,
        overlayBuilderMap: {
          'MainMenu': (context, SkyJumpGame game) => MainMenuOverlay(game: game),
          'HUD': (context, SkyJumpGame game) => HudOverlay(game: game),
          'GameOver': (context, SkyJumpGame game) => GameOverOverlay(game: game),
          'Shop': (context, SkyJumpGame game) => ShopOverlay(game: game),
        },
        initialActiveOverlays: const ['MainMenu'],
      ),
    );
  }
}

// ==========================================
// 3. FLAME GAME LOGIC (THE ENGINE)
// ==========================================

class SkyJumpGame extends FlameGame with HasCollisionDetection, TapDetector {
  // Game State
  double score = 0;
  int coins = 0;
  int diamonds = 0;
  double highestScore = 0;
  
  // Configuration
  late PlayerComponent player;
  late ObjectManager objectManager;
  
  // World Settings
  double gravity = 1200;
  double jumpForce = -750;
  bool isGameOver = false;
  bool isPaused = false;

  // Selected Character (0: Dog, 1: Cat, 2: Panda, 3: Rabbit)
  int selectedCharacterIndex = 0;
  final List<CharacterConfig> characters = [
    CharacterConfig(name: "الكلب الشجاع", color: Colors.orange, price: 0, ability: "توازن"),
    CharacterConfig(name: "القط السريع", color: Colors.blue, price: 100, ability: "قفزة مزدوجة"),
    CharacterConfig(name: "الباندا", color: Colors.black, price: 500, ability: "درع"),
    CharacterConfig(name: "الأرنب", color: Colors.pink, price: 1000, ability: "قفزة عالية"),
  ];

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    // Load saved data
    final prefs = await SharedPreferences.getInstance();
    coins = prefs.getInt('coins') ?? 0;
    highestScore = prefs.getDouble('high_score') ?? 0;
    
    // Setup Camera
    camera.viewfinder.anchor = Anchor.center;
    
    // Start Game Loop
    resetGame();
  }

  void resetGame() {
    // Clear existing
    children.whereType<Component>().forEach((c) => c.removeFromParent());
    
    isGameOver = false;
    score = 0;
    
    // Add Background (Simple gradient for now, can be parallax)
    add(RectangleComponent(
      size: size,
      paint: Paint()..color = const Color(0xFF1A1A2E), // Dark Night Sky
    ));

    // Add Player
    player = PlayerComponent(character: characters[selectedCharacterIndex]);
    add(player);
    
    // Add Object Manager (Spawns platforms/enemies)
    objectManager = ObjectManager();
    add(objectManager);

    // Initial Platform
    add(PlatformComponent(position: Vector2(0, 200), type: PlatformType.normal));
    
    resumeEngine();
  }

  void startGame() {
    overlays.remove('MainMenu');
    overlays.remove('GameOver');
    overlays.remove('Shop');
    overlays.add('HUD');
    resetGame();
  }

  void gameOver() async {
    if (isGameOver) return;
    isGameOver = true;
    pauseEngine();
    
    // Save Score
    if (score > highestScore) {
      highestScore = score;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('high_score', highestScore);
    }
    // Save Coins
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('coins', coins);

    overlays.remove('HUD');
    overlays.add('GameOver');
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (isGameOver) return;

    // Update Score based on height
    if (player.y < -score) {
      score = -player.y;
    }

    // Camera Follow Player (Only go up)
    if (player.y < camera.viewfinder.position.y + 100) {
       camera.viewfinder.position = Vector2(0, player.y - 100);
    }

    // Death Condition (Fall below camera)
    if (player.y > camera.viewfinder.position.y + size.y / 2) {
      gameOver();
    }
  }

  @override
  void onTapDown(TapDownInfo info) {
    // Simple tap to move towards tap side (simplified for mobile)
    if (info.eventPosition.global.x < size.x / 2) {
      player.moveLeft();
    } else {
      player.moveRight();
    }
  }
  
  @override
  void onTapUp(TapUpInfo info) {
    player.stopMoving();
  }
}

// ==========================================
// 4. GAME COMPONENTS (PLAYER, PLATFORMS)
// ==========================================

class CharacterConfig {
  final String name;
  final Color color;
  final int price;
  final String ability;
  CharacterConfig({required this.name, required this.color, required this.price, required this.ability});
}

class PlayerComponent extends PositionComponent with HasGameRef<SkyJumpGame>, CollisionCallbacks {
  final CharacterConfig character;
  Vector2 velocity = Vector2.zero();
  double moveSpeed = 400;
  int moveDirection = 0; // -1 left, 1 right, 0 stop

  PlayerComponent({required this.character}) : super(size: Vector2(40, 40), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    // Visual representation (Circle)
    add(CircleComponent(
      radius: 20,
      paint: Paint()..color = character.color,
    ));
    // Eyes
    add(CircleComponent(radius: 4, position: Vector2(10, 12), paint: Paint()..color = Colors.white));
    add(CircleComponent(radius: 4, position: Vector2(26, 12), paint: Paint()..color = Colors.white));
    
    // Hitbox
    add(RectangleHitbox());
    position = Vector2(0, 0);
  }

  void moveLeft() => moveDirection = -1;
  void moveRight() => moveDirection = 1;
  void stopMoving() => moveDirection = 0;

  void jump(double forceMultiplier) {
    velocity.y = gameRef.jumpForce * forceMultiplier;
    // Play sound effect here (mock)
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Horizontal Movement
    velocity.x = moveDirection * moveSpeed;
    
    // Gravity
    velocity.y += gameRef.gravity * dt;

    // Apply Velocity
    position += velocity * dt;

    // Screen Wrap (Pacman style)
    if (position.x > gameRef.size.x / 2) position.x = -gameRef.size.x / 2;
    if (position.x < -gameRef.size.x / 2) position.x = gameRef.size.x / 2;
  }

  @override
  void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollision(intersectionPoints, other);
    
    // Only jump if falling down and hitting top of platform
    if (velocity.y > 0 && other is PlatformComponent) {
      // Check if we are above the platform
      if (position.y < other.position.y - other.size.y / 2) {
        if (other.type == PlatformType.breakable) {
          other.breakPlatform();
        } 
        double boost = 1.0;
        if (other.type == PlatformType.boost) boost = 1.5;
        jump(boost);
      }
    } else if (other is EnemyComponent) {
      gameRef.gameOver();
    } else if (other is CoinComponent) {
      gameRef.coins++;
      other.removeFromParent();
    }
  }
}

enum PlatformType { normal, moving, breakable, boost }

class PlatformComponent extends PositionComponent with HasGameRef<SkyJumpGame> {
  final PlatformType type;
  double speed = 100;
  int direction = 1;

  PlatformComponent({required Vector2 position, required this.type}) 
      : super(position: position, size: Vector2(80, 20), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    Color color = Colors.green;
    if (type == PlatformType.moving) color = Colors.blue;
    if (type == PlatformType.breakable) color = Colors.brown;
    if (type == PlatformType.boost) color = Colors.redAccent;

    add(RectangleComponent(
      size: size,
      paint: Paint()..color = color,
    ));
    add(RectangleHitbox());
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (type == PlatformType.moving) {
      position.x += speed * direction * dt;
      if (position.x > gameRef.size.x / 2 - 50 || position.x < -gameRef.size.x / 2 + 50) {
        direction *= -1;
      }
    }
    
    // Cleanup if too far below
    if (position.y > gameRef.camera.viewfinder.position.y + gameRef.size.y) {
      removeFromParent();
    }
  }

  void breakPlatform() {
    removeFromParent();
    // Add particle effect here
  }
}

class CoinComponent extends PositionComponent with HasGameRef<SkyJumpGame> {
  CoinComponent({required Vector2 position}) 
      : super(position: position, size: Vector2(20, 20), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    add(CircleComponent(radius: 10, paint: Paint()..color = Colors.yellow));
    add(CircleComponent(radius: 7, paint: Paint()..color = Colors.amber));
    add(RectangleHitbox());
  }
}

class EnemyComponent extends PositionComponent with HasGameRef<SkyJumpGame> {
  EnemyComponent({required Vector2 position}) 
      : super(position: position, size: Vector2(40, 30), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    // Bird shape
    add(RectangleComponent(size: size, paint: Paint()..color = Colors.red));
    add(RectangleHitbox());
  }
}

class ObjectManager extends Component with HasGameRef<SkyJumpGame> {
  double nextSpawnY = 0;

  @override
  void update(double dt) {
    super.update(dt);
    
    // Spawn platforms as we go up
    final cameraTop = gameRef.camera.viewfinder.position.y - gameRef.size.y / 2;
    
    while (nextSpawnY > cameraTop - 100) {
      spawnLayer(nextSpawnY);
      nextSpawnY -= 120; // Distance between platforms
    }
  }

  void spawnLayer(double y) {
    final r = Random();
    double x = (r.nextDouble() * gameRef.size.x) - (gameRef.size.x / 2);
    
    // Determine type
    PlatformType type = PlatformType.normal;
    if (r.nextDouble() < 0.2) type = PlatformType.moving;
    else if (r.nextDouble() < 0.1) type = PlatformType.breakable;
    else if (r.nextDouble() < 0.05) type = PlatformType.boost;

    gameRef.add(PlatformComponent(position: Vector2(x, y), type: type));

    // Chance for Coin
    if (r.nextDouble() < 0.3) {
      gameRef.add(CoinComponent(position: Vector2(x, y - 40)));
    }

    // Chance for Enemy (only higher up)
    if (gameRef.score > 1000 && r.nextDouble() < 0.05) {
       gameRef.add(EnemyComponent(position: Vector2(x + (r.nextBool() ? 100 : -100), y - 100)));
    }
  }
}

// ==========================================
// 5. UI OVERLAYS (WIDGETS)
// ==========================================

class MainMenuOverlay extends StatelessWidget {
  final SkyJumpGame game;
  const MainMenuOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.purpleAccent, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("SKY JUMP LEGENDS", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
            const Text("أساطير القفز", style: TextStyle(fontSize: 24, color: Colors.purpleAccent)),
            const SizedBox(height: 20),
            Text("أعلى نتيجة: ${game.highestScore.toInt()}", style: const TextStyle(color: Colors.yellow, fontSize: 18)),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () => game.startGame(),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15)),
              child: const Text("ابدأ اللعب", style: TextStyle(fontSize: 24, color: Colors.white)),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                game.overlays.remove('MainMenu');
                game.overlays.add('Shop');
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text("المتجر والشخصيات", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

class GameOverOverlay extends StatelessWidget {
  final SkyJumpGame game;
  const GameOverOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.9),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("GAME OVER", style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white)),
            const Text("انتهت اللعبة", style: TextStyle(fontSize: 24, color: Colors.white)),
            const SizedBox(height: 20),
            Text("النتيجة: ${game.score.toInt()}", style: const TextStyle(fontSize: 30, color: Colors.yellow)),
            const SizedBox(height: 30),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  onPressed: () => game.startGame(),
                  icon: const Icon(Icons.refresh),
                  label: const Text("إعادة"),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: () {
                    game.overlays.remove('GameOver');
                    game.overlays.add('MainMenu');
                  },
                  icon: const Icon(Icons.home),
                  label: const Text("الرئيسية"),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class HudOverlay extends StatelessWidget {
  final SkyJumpGame game;
  const HudOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ValueListenableBuilder(
                  valueListenable: ValueNotifier(game.score), // In real app use proper notifier
                  builder: (context, value, child) => Text("Score: ${game.score.toInt()}", 
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 5, color: Colors.black)])),
                ),
                Row(
                  children: [
                    const Icon(Icons.monetization_on, color: Colors.yellow),
                    Text(" ${game.coins}", style: const TextStyle(color: Colors.white, fontSize: 20)),
                  ],
                )
              ],
            ),
            const Spacer(),
            // Touch Controls Hint
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(Icons.arrow_back_ios, color: Colors.white54, size: 40),
                Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 40),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class ShopOverlay extends StatefulWidget {
  final SkyJumpGame game;
  const ShopOverlay({super.key, required this.game});

  @override
  State<ShopOverlay> createState() => _ShopOverlayState();
}

class _ShopOverlayState extends State<ShopOverlay> {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 350,
        height: 600,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10)],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("المتجر", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    widget.game.overlays.remove('Shop');
                    widget.game.overlays.add('MainMenu');
                  },
                )
              ],
            ),
            Text("رصيدك: ${widget.game.coins} عملة", style: const TextStyle(color: Colors.orange, fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: widget.game.characters.length,
                itemBuilder: (context, index) {
                  final char = widget.game.characters[index];
                  final isSelected = widget.game.selectedCharacterIndex == index;
                  
                  return Card(
                    color: isSelected ? Colors.green.shade100 : Colors.white,
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: char.color),
                      title: Text(char.name),
                      subtitle: Text("القدرة: ${char.ability}"),
                      trailing: isSelected 
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : ElevatedButton(
                            onPressed: () {
                              setState(() {
                                widget.game.selectedCharacterIndex = index;
                              });
                            },
                            child: Text(char.price == 0 ? "اختر" : "${char.price}"),
                          ),
                    ),
                  );
                },
              ),
            ),
            const Divider(),
            const Text("المهام اليومية", style: TextStyle(fontWeight: FontWeight.bold)),
            const ListTile(
              leading: Icon(Icons.task_alt, color: Colors.green),
              title: Text("اقفز 100 مرة"),
              trailing: Text("50 عملة"),
            ),
          ],
        ),
      ),
    );
  }
}
